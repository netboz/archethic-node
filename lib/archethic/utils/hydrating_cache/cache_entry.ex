defmodule Archethic.Utils.HydratingCache.CacheEntry.StateData do
  @moduledoc """
  Struct describing the state of a cache entry FSM
  """

  defstruct running_func_task: :undefined,
            hydrating_func: :undefined,
            getters: [],
            ttl: :undefined,
            refresh_interval: :undefined,
            key: :undefined,
            value: :"$$undefined",
            timer_func: :undefined,
            timer_discard: :undefined
end

defmodule Archethic.Utils.HydratingCache.CacheEntry do
  @moduledoc """
  This module is a finite state machine implementing a cache entry.
  There is one such Cache Entry FSM running per registered key.

  It is responsible for :
  - receiving request to get the value for the key it is associated with
  - Run the hydrating function associated with this key
  - Manage various timers
  """
  alias Archethic.Utils.HydratingCache.CacheEntry
  @behaviour :gen_statem

  use Task
  require Logger

  def start_link([fun, key, ttl, refresh_interval]) do
    :gen_statem.start_link(__MODULE__, [fun, key, ttl, refresh_interval], [])
  end

  @impl :gen_statem
  def init([fun, key, ttl, refresh_interval]) do
    timer = :timer.send_interval(refresh_interval, self(), :hydrate)

    ## Hydrate the value
    {:ok, :running,
     %CacheEntry.StateData{
       timer_func: timer,
       hydrating_func: fun,
       key: key,
       ttl: ttl,
       refresh_interval: refresh_interval
     }}
  end

  @impl :gen_statem
  def callback_mode, do: [:handle_event_function, :state_enter]

  @impl :gen_statem
  def handle_event({:call, from}, {:get, _from}, :idle, data) do
    IO.puts("==> Get in idle state")
    ## Value is requested while fsm is iddle, return the value
    {:next_state, :idle, data, [{:reply, from, data.value}]}
  end

  def handle_event(:cast, {:get, from}, :idle, data) do
    ## Value is requested while fsm is iddle, return the value
    send(from, {:ok, data.value})
    {:next_state, :idle, data}
  end

  ## Call for value while hydrating function is running and we have no previous value
  ## We register the caller to send value later on, and we indicate caller to block
  def handle_event({:call, _from}, {:get, from}, :running, data)
      when data.value == :"$$undefined" do
    previous_getters = data.getters

    {:keep_state, %CacheEntry.StateData{data | getters: previous_getters ++ [from]},
     [{:reply, from, {:ok, :answer_delayed}}]}
  end

  ## Call for value while hydrating function is running and we have a previous value
  ## We return the value to caller
  def handle_event({:call, from}, {:get, _from}, :running, data) do
    {:next_state, :running, data, [{:reply, from, data.value}]}
  end

  ## Getting value when a function is running and no previous value is available
  ## Register this getter to send value later on
  def handle_event(:cast, {:get, from}, :running, data) when data.value == :"$$undefined" do
    previous_getters = data.getters
    {:next_state, :running, %CacheEntry.StateData{data | getters: previous_getters ++ [from]}}
  end

  def handle_event(:cast, {:get, from}, :running, data) do
    ## Getting value while function is running but previous value is available
    ## Return vurrent value
    send(from, {:ok, data.value})
    {:next_state, :running, data}
  end

  def handle_event({:call, from}, {:register, fun, key, ttl, refresh_interval}, :running, data) do
    ## Registering a new hydrating function while previous one is running

    ## We stop the hydrating task if it is already running
    case data.running_func_task do
      pid when is_pid(pid) -> Process.exit(pid, :brutal_kill)
      _ -> :ok
    end

    ## And the timers triggering it and discarding value
    _ = :timer.cancel(data.timer_func)
    _ = :timer.cancel(data.timer_discard)

    ## Start new timer to hydrate at refresh interval
    timer = :timer.send_interval(refresh_interval, self(), :hydrate)

    ## We trigger the update ( to trigger or not could be set at registering option )
    {:repeat_state,
     %CacheEntry.StateData{
       data
       | hydrating_func: fun,
         key: key,
         ttl: ttl,
         refresh_interval: refresh_interval,
         timer_func: timer
     }, [{:reply, from, :ok}]}
  end

  def handle_event({:call, from}, {:register, fun, key, ttl, refresh_interval}, _state, data) do
    IO.puts("Registering new hydrating function #{inspect(fun)} for key #{inspect(key)}")
    ## Setting hydrating function in other cases
    ## Hydrating function not running, we just stop the timers
    _ = :timer.cancel(data.timer_func)
    _ = :timer.cancel(data.timer_discard)

    ## Fill state with new hydrating function parameters
    data =
      Map.merge(data, %{
        :hydrating_func => fun,
        :ttl => ttl,
        :refresh_interval => refresh_interval
      })

    timer = :timer.send_interval(refresh_interval, self(), :hydrate)

    ## We trigger the update ( to trigger or not could be set at registering option )
    {:next_state, :running,
     %CacheEntry.StateData{
       data
       | hydrating_func: fun,
         key: key,
         ttl: ttl,
         refresh_interval: refresh_interval,
         timer_func: timer
     }, [{:reply, from, :ok}]}
  end

  def handle_event(:info, :hydrate, :idle, data) do
    ## Time to rehydrate
    ## Hydrating the key, go to running state
    {:next_state, :running, data}
  end

  def handle_event(:enter, _event, :running, data) do
    ## At entering running state, we start the hydrating task
    me = self()

    hydrating_task =
      spawn(fn ->
        value = data.hydrating_func.()
        :gen_statem.cast(me, {:new_value, data.key, value})
      end)

    ## we stay in running state
    {:next_state, :running, %CacheEntry.StateData{data | running_func_task: hydrating_task}}
  end

  def handle_event(:info, :discarded, state, data) do
    ## Value is discarded

    Logger.warning(
      "Key :#{inspect(data.key)}, Hydrating func #{inspect(data.hydrating_func)} discarded"
    )

    {:next_state, state, %CacheEntry.StateData{data | value: :discarded}}
  end

  def handle_event(:cast, {:new_value, key, {:ok, value}}, :running, data) do
    ## Stop timer on value ttl
    _ = :timer.cancel(data.timer_discard)

    ## We got result from hydrating function
    Logger.debug(
      "Key :#{inspect(data.key)}, Hydrating func #{inspect(data.hydrating_func)} got value #{inspect({key, value})}"
    )

    ## notify waiiting getters
    Enum.each(data.getters, fn {pid, _ref} ->
      IO.puts("Sending value to #{inspect(pid)}")
      send(pid, {:ok, value})
    end)

    ## We could do error control here, like unregistering the running func.
    ## atm, we will keep it
    _ = :timer.cancel(data.timer_discard)

    me = self()
    {:ok, new_timer} = :timer.send_after(data.ttl, me, :discarded)

    {:next_state, :idle,
     %CacheEntry.StateData{
       data
       | running_func_task: :undefined,
         value: {:ok, value},
         getters: [],
         timer_discard: new_timer
     }}
  end

  def handle_event(:cast, {:new_value, key, {:error, reason}}, :running, data) do
    ## Got error new value for key
    Logger.warning(
      "Key :#{inspect(data.key)}, Hydrating func #{inspect(data.hydrating_func)} got error value #{inspect({key, {:error, reason}})}"
    )

    {:next_state, :idle, %CacheEntry.StateData{data | running_func_task: :undefined}}
  end

  def handle_event(_type, _event, _state, data) do
    {:keep_state, data}
  end
end
