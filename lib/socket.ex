defmodule HTTProcket.Socket do
  require Logger
  @moduledoc """
  Wrapper module for reading/writing data to a UNIX domain socket.
  """

  @doc """
  Close an open socket.
  """
  def close(sock), do: :procket.close(sock)

  @doc """
  Send data to a socket and return its response.
  """
  def request(data, sock) when is_integer(sock) do
    :ok = write(sock, data)
    get_data(sock)
  end

  def request(data, file) when is_binary(file) do
    sock = connect(file)
    response = request(data, sock)
    close(sock)
    response
  end

  @doc """
  Opens a socket to the file location, sends the data, and closes the socket.
  """
  def write(file, data) when is_binary(file) do
    sock = connect(file)
    write(sock, data)
    close(sock)
  end

  @doc """
  Sends data to the open socket.
  """
  def write(sock, data) when is_integer(sock) do
    :procket.write(sock, data <> "\n")
  end

  @doc """
  Opens a socket to the file location.
  """
  def connect(file) do
    unix_socket = domain_socket(file)
    {:ok, sock} = :procket.socket(1, 1, 0)
    :procket.connect(sock, unix_socket)
    sock
  end

  defp domain_socket(file) do
    len = byte_size(file)
    pad_size = (:procket.unix_path_max() - len) * 8
    :procket.sockaddr_common(1, len) <> file <> << 0 :: size(pad_size) >>
  end

  @doc """
  From the open socket, read in any waiting data.
  """
  def read_chunk(sock, size) do
    case :procket.read(sock, size) do
      {:ok, data} when byte_size(data) > 0 -> data
      {:error, :eagain} -> nil
    end
  end

  def read_line(sock) when is_integer(sock) do
    read_one_byte = fn -> read_chunk(sock, 1) end
    line = Stream.repeatedly(read_one_byte)
      |> Stream.take_while(&(&1 != "\n" and &1 != nil))
      |> Enum.into ""

    case line do
      "" -> read_line(sock)
      _ -> line <> "\n"
    end
  end

  @read_size 1024
  #
  # Keeps trying to read a chunk of data until the data has been thoroughly read
  #
  defp get_data(sock), do: read_chunk(sock, @read_size) |> get_data("", sock)
  defp get_data(data, sock), do: read_chunk(sock, @read_size) |> get_data(data, sock)
  defp get_data(nil, "", sock), do: get_data("", sock)
  defp get_data(nil, data, _sock), do: data
  defp get_data(new_data, data, sock), do: get_data(data <> new_data, sock)
end
