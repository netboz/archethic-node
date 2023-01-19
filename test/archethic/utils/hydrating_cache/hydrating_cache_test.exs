defmodule HydratingCacheTest do
  alias Archethic.Utils.HydratingCache
  use ExUnit.Case
  require Logger

  test "If `key` is not associated with any function, return `{:error, :not_registered}`" do
    {:ok, pid} = HydratingCache.start_link(:test_service)
    assert HydratingCache.get(pid, "unexisting_key") == {:error, :not_registered}
  end

  test "If value stored, it is returned immediatly" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    result =
      HydratingCache.register_function(
        pid,
        fn ->
          {:ok, 1}
        end,
        "simple_func",
        50_000,
        10_000
      )

    assert result == :ok
    ## WAit a little to be sure value is registered and not being refreshed
    :timer.sleep(500)
    r = HydratingCache.get(pid, "simple_func", 10_000)
    assert r == {:ok, 1}
  end

  test "Getting value for key while function is running first time make process wait and return value" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    result =
      HydratingCache.register_function(
        pid,
        fn ->
          Logger.info("Hydrating function Sleeping 3 secs")
          :timer.sleep(3000)
          {:ok, 1}
        end,
        "test_long_function",
        50_000,
        9000
      )

    assert result == :ok

    r = HydratingCache.get(pid, "test_long_function", 10_000)
    assert r == {:ok, 1}
  end

  test "Getting value for key while function is running first time returns timeout after ttl" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    result =
      HydratingCache.register_function(
        pid,
        fn ->
          Logger.info("Hydrating function Sleeping 3 secs")
          :timer.sleep(3000)
          {:ok, 1}
        end,
        "test_get_ttl",
        50_000,
        9000
      )

    assert result == :ok

    ## get and wait up to 1 second
    r = HydratingCache.get(pid, "test_get_ttl", 1000)
    assert r == {:error, :timeout}
  end

  test "Hydrating function runs periodically" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    :persistent_term.put("test", 0)

    result =
      HydratingCache.register_function(
        pid,
        fn ->
          IO.puts("Hydrating function incrementing value")
          value = :persistent_term.get("test")
          value = value + 1
          :persistent_term.put("test", value)
          {:ok, value}
        end,
        "test_inc",
        50000,
        1000
      )

    assert result == :ok

    :timer.sleep(5000)
    {:ok, value} = HydratingCache.get(pid, "test_inc", 3000)

    assert value >= 5
  end

  test "Update hydrating function while another one is running returns new hydrating value from new function" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    result =
      HydratingCache.register_function(
        pid,
        fn ->
          :timer.sleep(5000)
          {:ok, 1}
        end,
        "test_reregister",
        50000,
        10000
      )

    assert result == :ok

    _result =
      HydratingCache.register_function(
        pid,
        fn ->
          {:ok, 2}
        end,
        "test_reregister",
        50000,
        10000
      )

    :timer.sleep(5000)
    {:ok, value} = HydratingCache.get(pid, "test_reregister", 4000)

    assert value == 2
  end

  test "Getting value while function is running and previous value is available returns value" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          {:ok, 1}
        end,
        "test_reregister",
        50000,
        10000
      )

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          :timer.sleep(5000)
          {:ok, 2}
        end,
        "test_reregister",
        50000,
        10000
      )

    {:ok, value} = HydratingCache.get(pid, "test_reregister", 4000)

    assert value == 1
  end

  test "Two hydrating function can run at same time" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          :timer.sleep(5000)
          {:ok, :result_timed}
        end,
        "timed_value",
        80000,
        70000
      )

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          {:ok, :result}
        end,
        "direct_value",
        80000,
        70000
      )

    ## We query the value with timeout smaller than timed function
    {:ok, _value} = HydratingCache.get(pid, "direct_value", 2000)
  end

  test "Querying key while first refreshed will block the calling process until refreshed and provide the value" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          :timer.sleep(4000)
          {:ok, :valid_result}
        end,
        "delayed_result",
        80000,
        70000
      )

    ## We query the value with timeout smaller than timed function
    assert {:ok, :valid_result} = HydratingCache.get(pid, "delayed_result", 5000)
  end

  test "Querying key while first refreshed will block the calling process until timeout" do
    {:ok, pid} = HydratingCache.start_link(:test_service)

    _ =
      HydratingCache.register_function(
        pid,
        fn ->
          :timer.sleep(2000)
          {:ok, :valid_result}
        end,
        "delayed_result",
        80000,
        70000
      )

    ## We query the value with timeout smaller than timed function
    result = HydratingCache.get(pid, "delayed_result", 1000)
    assert result == {:error, :timeout}
  end
end
