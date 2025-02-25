defmodule Archethic.P2P.Listener do
  @moduledoc false

  use GenServer
  @vsn Mix.Project.config()[:version]

  alias Archethic.P2P.ListenerProtocol

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    transport = Keyword.get(opts, :transport)
    port = Keyword.get(opts, :port)

    {:ok, {transport, port}}
  end

  def listen() do
    GenServer.cast(__MODULE__, :start_listener)
  end

  def handle_cast(:start_listener, {transport, port}) do
    ranch_transport =
      case transport do
        :tcp ->
          :ranch_tcp

        _ ->
          transport
      end

    case :ranch.start_listener(
           :archethic_p2p,
           ranch_transport,
           %{socket_opts: [{:port, port}, {:backlog, 4096}], num_acceptors: 100},
           ListenerProtocol,
           [:binary, packet: 4, active: :once, keepalive: true, reuseaddr: true]
         ) do
      {:ok, listener_pid} ->
        Logger.info("P2P #{transport} Endpoint running on port #{port}")

        {:noreply, %{listener_pid: listener_pid}}

      {:error, :eaddrinuse} ->
        Logger.error(
          "P2P #{transport} Endpoint cannot listen on port #{port}. Port already in use"
        )

        System.stop(1)
    end
  end
end
