defmodule Desk.Hidden do
  @moduledoc false
  # What the acceptance tests share. `move/2` is the ticket's move as the app names it at this step.

  # by apply: the helper is compiled at every step, the ones before the function exists too
  def move(ticket, to), do: apply(Desk.Tickets, :transition, [ticket, to])

  def ticket!(attrs \\ %{}) do
    {:ok, ticket} =
      %{subject: "Printer on fire", body: "It is.", requester_email: "ann@example.com"}
      |> Map.merge(Map.new(attrs))
      |> Desk.Tickets.create_ticket()

    ticket
  end

  def agent!(name, attrs \\ %{}) do
    {:ok, agent} =
      %{name: name, email: String.downcase(name) <> "@desk.example"}
      |> Map.merge(Map.new(attrs))
      |> then(&apply(Desk.Staff, :create_agent, [&1]))

    agent
  end

  # a ticket filed at `at`, which no function of the app lets a caller choose
  def filed!(at, attrs \\ %{}) do
    ticket = ticket!(attrs)

    ticket
    |> Ecto.Changeset.change(inserted_at: at)
    |> Desk.Repo.update!()
  end

  def through!(ticket, statuses) do
    Enum.reduce(statuses, ticket, fn to, ticket ->
      {:ok, ticket} = move(ticket, to)
      ticket
    end)
  end
end
