defmodule SignEx.HTTP do
  @moduledoc """
  Verify the integrity of HTTP requests.

  `SignEx.HTTP` validates the integrity of HTTP requests by checking digest and signature.
  The digest header contains the digest of the request body, useing a configurable hash algorithm.
  The authorization header contains a signature and parameters that secure the request headers.

  *NOTE the signature will sign a subset of the headers,
  It is required for the digest header to be in this list so guarantee the integrity of the whole request.*

  - [Specification for the contents of the digest header](https://tools.ietf.org/html/rfc3230)
  - [Sepcification for signing HTTP Messages](https://tools.ietf.org/html/draft-cavage-http-signatures-05)

  """

  @doc """
  Create a signature header string for a list of headers

  Will sign all headers passed in but has no knowledge of path psudo header.
  """

  def sign(request = %{
    method: _method,
    path: _path,
    query_string: _query_string,
    headers: headers,
    body: body
    }, keypair) do
      headers_to_sign = [{"(request-target)", request_target(request)} | headers]
      |> Enum.into(%{})
      case SignEx.sign(body, headers_to_sign, keypair) do
        {:ok, {%{"digest" => digest}, signature_params}} ->
          {:ok, signature_string} = SignEx.Parameters.serialize(signature_params)
          headers = headers ++ [
            {"digest", digest},
            {"authorization", "Signature "<> signature_string}
          ]
          %{request | headers: headers}
      end
  end

  def verified?(request, keystore) do
    case verify(request, keystore) do
      {:ok, _} ->
        true
      {:error, _} ->
        false
    end
  end


  def verify(request = %{
    method: _method,
    path: _path,
    headers: headers,
    body: body
    }, keystore) do
      headers = Enum.into(headers, %{})
      case Map.fetch(headers, "authorization") do
        {:ok, "Signature " <> signature_string} ->
          case SignEx.Parameters.parse(signature_string) do
            {:ok, parameters} ->
              request_target = request_target(request)
              headers = Map.put(headers, "(request-target)", request_target)
              case SignEx.verify(body, headers, parameters, keystore) do
                {:ok, _} ->
                  {:ok, request}
                {:error, reason} ->
                  {:error, reason}
              end
            {:error, reason} ->
              {:error, reason}
          end
        {:ok, authorization} ->
          {:error, {:unrecognised_authorization, authorization}}
        :error ->
          {:error, :missing_authorization_header}
      end
  end

  defp request_target(%{method: method, path: path, query_string: query_string}) do
    method = method |> to_string |> String.downcase
    base = "#{method} #{path}"
    case query_string do
      none when none in [nil, ""] ->
        base
      _ ->
        "#{base}?#{query_string}"
    end
  end

  require Logger

  def parse_parameters(str) do
    Logger.warn("Depreciated: Use `SignEx.Parameters.parse`")
    SignEx.Parameters.parse(str)
  end
end
