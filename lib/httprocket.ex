defmodule HTTProcket do
  require Logger

  @doc """
  Makes a GET request to the UNIX socket at "file".
  """
  def get(file, resource, body \\ "", headers \\ []) do
    request(file, :get, resource, body, headers)
  end

  @doc """
  Makes a POST request to the UNIX socket at "file".
  """
  def post(file, resource, body \\ "", headers \\ []) do
    request(file, :post, resource, body, headers)
  end

  @doc """
  Makes a PUT request to the UNIX socket at "file".
  """
  def put(file, resource, body \\ "", headers \\ []) do
    request(file, :put, resource, body, headers)
  end

  @doc """
  Makes a DELETE request to the UNIX socket at "file".
  """
  def delete(file, resource, body \\ "", headers \\ []) do
    request(file, :delete, resource, body, headers)
  end

  @doc """
  Makes an HTTP request and returns the result. A new handler will be opened to
  the socket and closed when the request is finished.
  """
  def request(file, method, resource, body, headers) when is_binary(body) do
    headers = Enum.into(headers, %{"Content-Length" => String.length(body)})

    format_request(method, resource, headers, body)
    |> send_request(file)
    |> read_response
  end

  @doc """
  JSON-encodes the request body into a string before sending.
  """
  def request(file, method, resource, body, headers) do
    body = Poison.encode!(body)
    headers = Enum.into(headers, %{"Content-Type" => "application/json"})
    request(file, method, resource, body, headers)
  end

  @doc """
  Reads the HTTP response from an open socket.
  """
  def read_response(socket) do
    {:ok, pid} = HTTProcket.Request.start_link
    {code, body} = read_socket(pid, socket)
    HTTProcket.Socket.close(socket)

    {code, body}
  end

  @doc """
  Turns a dictionary of headers into a string formatted to go in an HTTP request.
  """
  def encode_headers(headers) do
    headers
    |> Enum.map(&(Tuple.to_list(&1) |> Enum.join(": ")))
    |> Enum.join("\r\n")
  end


  defp read_socket(pid, socket) do
    HTTProcket.Socket.read_line(socket)
    |> HTTProcket.Request.parse(pid)
    |> check_read_state(pid, socket)
  end

  defp check_read_state(%{state: :done, body: body, status: status}, _pid, _sock), do: {status, body}
  defp check_read_state(_state, pid, sock), do: read_socket(pid, sock)

  defp format_request(method, resource, headers, body) do
    method = method |> to_string |> String.upcase
    "#{method} #{resource} HTTP/1.1\r\n" <>
    encode_headers(headers) <> "\r\n" <>
    body <> "\r\n"
  end

  defp send_request(req, file) do
    Logger.debug("Sending #{inspect req} to #{file}")
    sock = HTTProcket.Socket.connect(file)
    :ok = HTTProcket.Socket.write(sock, req)
    sock
  end
end
