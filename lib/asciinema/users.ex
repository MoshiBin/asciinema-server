defmodule Asciinema.Users do
  import Ecto.Query, warn: false
  import Ecto, only: [assoc: 2]
  alias Asciinema.{Repo, User, ApiToken, Asciicasts, Asciicast}

  def create_asciinema_user!() do
    attrs = %{username: "asciinema",
              name: "asciinema",
              email: "support@asciinema.org"}

    user = case Repo.get_by(User, username: "asciinema") do
             nil ->
               %User{}
               |> User.create_changeset(attrs)
               |> Repo.insert!
             user ->
               user
           end

    if Repo.count(assoc(user, :asciicasts)) == 0 do
      upload = %Plug.Upload{path: "resources/welcome.json",
                            filename: "asciicast.json",
                            content_type: "application/json"}

      Repo.transaction(fn ->
        {:ok, asciicast} = Asciicasts.create_asciicast(user, upload, nil)

        asciicast
        |> Asciicast.update_changeset(%{private: false, snapshot_at: 76.2})
        |> Repo.update!
      end)
    end

    :ok
  end

  def authenticate(api_token) do
    q = from u in User,
      join: at in ApiToken,
      on: at.user_id == u.id,
      select: {u, at.revoked_at},
      where: at.token == ^api_token

    case Repo.one(q) do
      nil ->
        {:error, :token_not_found}
      {%User{} = user, nil} ->
        {:ok, user}
      {%User{}, _} ->
        {:error, :token_revoked}
    end
  end

  def get_user_with_api_token(username, api_token) do
    case authenticate(api_token) do
      {:ok, %User{} = user} ->
        user
      {:error, :token_revoked} ->
        nil
      {:error, :token_not_found} ->
        create_user_with_api_token(username, api_token)
    end
  end

  def create_user_with_api_token(username, api_token) do
    user_changeset = User.temporary_changeset(username)

    {_, result} = Repo.transaction(fn ->
      with {:ok, %User{} = user} <- Repo.insert(user_changeset),
           api_token_changeset = ApiToken.create_changeset(user, api_token),
           {:ok, %ApiToken{}} <- Repo.insert(api_token_changeset) do
        user
      else
        _otherwise -> Repo.rollback(nil)
      end
    end)

    result
  end

  def get_api_token!(token) do
    Repo.get_by!(ApiToken, token: token)
  end

  def revoke_api_token!(api_token) do
    api_token
    |> ApiToken.revoke_changeset
    |> Repo.update!
  end

  def merge!(dst_user, src_user) do
    Repo.transaction(fn ->
      asciicasts_q = from(assoc(src_user, :asciicasts))
      Repo.update_all(asciicasts_q, set: [user_id: dst_user.id, updated_at: Timex.now])
      api_tokens_q = from(assoc(src_user, :api_tokens))
      Repo.update_all(api_tokens_q, set: [user_id: dst_user.id, updated_at: Timex.now])
      expiring_tokens_q = from(assoc(src_user, :expiring_tokens))
      Repo.delete_all(expiring_tokens_q)
      Repo.delete!(src_user)
      dst_user
    end)
  end
end
