defmodule Studysync.AI.Client do
  @moduledoc """
  Thin wrapper around ReqLLM for Anthropic text generation.

  Reads ANTHROPIC_API_KEY from the application environment, which is set
  from the system environment variable of the same name. Falls back to
  ReqLLM's own key-loading logic (env vars, .env files) when no app config
  is present, so the dev workflow of dropping the key in .env still works.
  """

  @model "anthropic:claude-haiku-4-5"

  @doc """
  Send `messages` to Claude and return the generated text.

  `messages` may be:
    - a plain string (treated as a user message)
    - a list of `%{role: "user"|"assistant", content: "..."}` maps

  Accepts the same `opts` as `ReqLLM.generate_text/3` — e.g. `max_tokens:`,
  `temperature:`.

  Returns `{:ok, text}` on success, `{:error, reason}` on failure.
  """
  @spec complete(String.t() | list(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def complete(messages, opts \\ []) do
    base_opts = build_opts()
    merged = Keyword.merge(base_opts, opts)

    case ReqLLM.generate_text(@model, messages, merged) do
      {:ok, response} ->
        case ReqLLM.Response.text(response) do
          nil -> {:error, :empty_response}
          text -> {:ok, text}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_opts do
    case Application.get_env(:studysync, :anthropic_api_key) ||
           System.get_env("ANTHROPIC_API_KEY") do
      nil -> []
      key -> [api_key: key]
    end
  end
end
