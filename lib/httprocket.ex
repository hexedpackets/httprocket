defmodule HTTProcket do
  use GenServer
  require Logger

  @doc """
  Module for parsing HTTP responses from a UNIX Socket. Possible states are:

  :init, :chunk_start, :content, :done
  """

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

  def parse(line, pid), do: GenServer.call(pid, {:parse, line})
  def result(pid), do: GenServer.call(pid, :result)

  def handle_call({:parse, line}, _from, state) do
    Logger.debug "Trying to parse: #{line}"
    new_state = parse_line(line, state)
    {:reply, new_state, new_state}
  end

  def handle_call(:result, _from, state) do
    {:reply, state, state}
  end


  @doc """
  Handles routing the parsing of the line according to how much of the message has
  already been parsed.
  """
  def parse_line("\r\n", state = %{state: :init, headers: %{encoding: "chunked"}}) do
    Dict.put(state, :state, :chunk_start)
  end
  def parse_line("\r\n", state = %{state: :init}) do
    Dict.put(state, :state, :content)
  end

  def parse_line(line, state = %{state: :init}) do
    line |> String.rstrip |> parse_header(state)
  end

  @doc """
  Indicates the end of a chunk-encoded stream of data.
  """
  def parse_line("0\r\n", state = %{state: :chunk_start}) do
    %{state | state: :done}
  end
  def parse_line("\r\n", state = %{state: :chunk_start}), do: state
  def parse_line(length, state = %{state: :chunk_start}) do
    length = length |> String.rstrip |> hex_to_decimal
    %{state | state: :content, chunk_length: length, chunk_read: 0}
  end

  @doc """
  Parse out a normal content bearing line.
  """
  def parse_line(line, state = %{state: :content}), do: parse_body(line, state)

  @doc """
  Parses out the initial line of an HTTP response.
  """
  def parse_header("HTTP/1.1 " <> line, state) do
    state = put_in(state[:headers][:version], 1.1)
    parse_status_code(line, state)
  end
  def parse_header("HTTP/1.0 " <> line, state) do
    state = put_in(state[:headers][:version], 1.0)
    parse_status_code(line, state)
  end

  @doc """
  Parses various headers from an HTTP response.
  """
  def parse_header("Content-Length: " <> length, state) do
    length = String.to_integer(length)
    state = put_in(state[:headers][:content_length], length)
    %{state | chunk_length: length}
  end
  def parse_header("Content-Type: " <> type, state) do
    put_in(state[:headers][:content_type], type)
  end
  def parse_header("Transfer-Encoding: " <> encoding, state) do
    put_in(state[:headers][:encoding], encoding)
  end
  def parse_header("Date: " <> date, state) do
    put_in(state[:headers][:date], date)
  end

  def parse_body(line, state) do
    total_read = state[:chunk_read] + String.length(line)
    %{state | chunk_read: total_read, body: state[:body] <> line}
        |> check_length
  end

  @doc """
  Parses the status code as an integer.
  """
  def parse_status_code(<< first::size(8), second::size(8), third::size(8), _rest::binary >>, state) do
    code = [first, second, third] |> to_string |> String.to_integer
    %{state | status: code} |> check_status_code
  end

  #
  # Takes a hex string and converts it to its decimal value.
  #
  defp hex_to_decimal(hex) do
    hex |> String.to_char_list |> List.to_integer(16)
  end

  defp check_length(state = %{state: :content, headers: %{encoding: "chunked"},
                 chunk_length: chunk_length,
                 chunk_read: chunk_read}) when chunk_length - chunk_read <= 0 do
    %{state | state: :chunk_start, chunk_length: nil}
  end

  defp check_length(state = %{state: :content,
                 chunk_length: chunk_length,
                 chunk_read: chunk_read}) when chunk_length - chunk_read <= 0 do
    %{state | state: :done, chunk_length: nil}
  end

  defp check_length(state), do: state

  # A 204 indicates no content and the result should be returned without trying to read the body
  defp check_status_code(state = %{status: 204}) do
    %{state | state: :done}
  end
  defp check_status_code(state), do: state
end
