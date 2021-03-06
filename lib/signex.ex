defmodule SignEx do
  require Logger
  require SignEx.Algorithm
  alias SignEx.Algorithm
  alias SignEx.Helper

  @digest_algorithm Algorithm.default_digest()
  @allowed_algorithms Algorithm.allowed_strings()

  # TODO rename this to sign_request
  @spec sign(body :: term, metadata :: map, keypair :: map)
    :: {:ok, {metadata :: map, %SignEx.Parameters{}}} | {:error, atom}
  def sign(_body, %{"signature" => _anything}, _keypair) do
    {:error, :already_signed}
  end
  def sign(body, metadata = %{}, keypair = %{public_key: public_key, private_key: private_key}) when
      is_binary(body) and is_binary(public_key) and is_binary(private_key) do
    metadata = Map.merge(metadata, %{"digest" => generate_digest(body)})
    parameters = SignEx.Signer.sign(metadata, keypair)
    {:ok, {metadata, parameters}}
  end


  def signature_valid?(headers, params, public_key) do
    case validate_signature(headers, params, public_key) do
      {:ok, _} ->
        true
      {:error, _} ->
        false
    end
  end
  def validate_signature(
    headers,
    params = %SignEx.Parameters{algorithm: algorithm_str},
    public_key) when is_binary(public_key) and algorithm_str in @allowed_algorithms
  do
    algorithm = Algorithm.new(algorithm_str)
    case Base.decode64(params.signature) do
      {:ok, signature} ->
        case Helper.fetch_keys(headers, params.headers) do
          {:ok, ordered_headers} ->
            signing_string = Helper.compose_signing_string(ordered_headers)
            :public_key.verify(signing_string, algorithm.digest, signature, Helper.decode_key(public_key))
            |> if do
              {:ok, :valid}
            else
              {:error, :signature_incorrect} 
            end
          {:error, reason} ->
            {:error, reason}
        end
      :error ->
        {:error, :invalid_signature_encoding}
    end
  end


  def verified?(body, metadata, params, keystore) do
    case verify(body, metadata, params, keystore) do
      {:ok, _} ->
        true
      {:error, _} ->
        false
    end
  end


  # TODO rename this to verify_request
  def verify(body, metadata = %{}, params= %SignEx.Parameters{}, keystore) when
      is_binary(body) do
    case fetch_key(keystore, params.key_id) do
      {:ok, public_key} ->
        case Map.fetch(metadata, "digest") do
          {:ok, full_digest} ->
            case validate_digest(body, full_digest) do
              {:ok, _} ->
                validate_signature(metadata, params, public_key)
              {:error, reason} ->
                {:error, reason}
            end
          :error ->
            {:error, :missing_digest_metadata}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def generate_digest(body, digest_algorithm \\ @digest_algorithm) do
    Algorithm.humanize_digest(digest_algorithm) <> "=" <> Base.encode64(digest_content(body, digest_algorithm))
  end

  def digest_content(content, digest_algorithm \\ @digest_algorithm) do
    :crypto.hash(digest_algorithm, content)
  end

  def validate_digest(content, full_digest) do
    case full_digest_destruct(full_digest) do
      {:ok, {digest_algorithm, digest}} ->
        case Base.decode64(digest) do
          {:ok, digest} ->
            if digest == digest_content(content, digest_algorithm) do
              {:ok, content}
            else
              {:error, :digest_not_for_content}
            end
          :error ->
            {:error, :invalid_digest_encoding}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end
  def digest_valid?(content, full_digest) do
    case validate_digest(content, full_digest) do
      {:ok, _} ->
        true
      {:error, _} ->
        false
    end
  end

  def signature_params(str) do
    Logger.warn("Depreciated: Use `SignEx.Parameters.parse`")

    SignEx.Parameters.parse(str)
  end

  defp fetch_key(public_key, _id) when is_binary(public_key) do
    {:ok, public_key}
  end
  defp fetch_key(keystore, id) when is_function(keystore, 1) do
    keystore.(id)
  end

  defp full_digest_destruct(full_digest) do
    with {digest_algorithm_str, digest_str} <- String.split_at(full_digest, 7),
         digest_algorithm <- normalize_digest_algorithm(digest_algorithm_str),
         true <- Algorithm.allowed_digest?(digest_algorithm)
    do
      {:ok, {String.to_atom(digest_algorithm), String.trim_leading(digest_str, "=")}}
    else
      _ ->
        {:error, :parsing_full_digest}
    end
  end

  defp normalize_digest_algorithm(digest_algorithm_str) do
    digest_algorithm_str
    |> String.replace("-", "")
    |> String.downcase()
  end


  @spec sign_message(binary, digest :: atom, keypair :: map)
  :: {:ok, signature :: String.t} | {:error, atom}

  def sign_message(message, digest, %{public_key: _public_key, private_key: private_key}) do
    if digest in Algorithm.available_digests() do
      signature = SignEx.Signer.sign_message(message, private_key, digest)
      {:ok, signature}
    else
      {:error, :invalid_digest}
    end
  end


  @spec verify_message(message :: String.t, digest :: atom, signature :: String.t, public_key :: String.t)
  :: {:ok, encryption_type :: atom} | {:error, atom}

  def verify_message(message, digest, signature, public_key) do
    if digest in Algorithm.available_digests() do
      case Base.decode64(signature) do
        {:ok, decoded_signature} ->
          decoded_key = Helper.decode_key(public_key)
          if :public_key.verify(message, digest, decoded_signature, decoded_key) do
            {:ok, Helper.encryption_type(decoded_key)}
          else
            {:error, :invalid_signature}
          end
        :error ->
          {:error, :invalid_signature_encoding}
      end
    else
      {:error, :invalid_digest}
    end
  end

end
