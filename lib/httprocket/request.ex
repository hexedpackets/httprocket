defmodule HTTProcket.Request do
  @moduledoc """
  Module for parsing HTTP responses from a UNIX Socket. Possible states are:

  :init, :chunk_start, :content, :done
  """

  use GenServer
  require Logger

  @doc false
  def start_link do
    state = %{
      headers: %{},
      status: nil,
      body: "",
      state: :init,

      chunk_length: nil,
      chunk_read: 0,
    }
    GenServer.start_link(__MODULE__, state)
  end

  @doc false
  def parse(line, pid), do: GenServer.call(pid, {:parse, line})
  @doc false
  def result(pid), do: GenServer.call(pid, :result)

  @doc """
  Parses a single line of output from a UNIX socket.
  """
  def handle_call({:parse, line}, _from, state) do
    Logger.debug "Trying to parse: #{line}"
    new_state = HTTProcket.Parser.parse_line(line, state)
    {:reply, new_state, new_state}
  end

  @doc """
  Returns the current state with all parsed output.
  """
  def handle_call(:result, _from, state) do
    {:reply, state, state}
  end
end
