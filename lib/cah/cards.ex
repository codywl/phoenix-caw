defmodule Cah.Cards do
  @external_resource "priv/cards.txt"
  @path Application.app_dir(:cah, "priv/cards.txt")
  [white_cards, black_cards] =
    File.read!(@path)
    |> String.split(~r/^-+$/m, parts: 2)
    |> Enum.map(fn section ->
      section
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    end)

  @white_cards white_cards
  @black_cards black_cards

  def text({:white, i}) do
    Enum.at(@white_cards, i)
  end

  def text({:black, i}) do
    Enum.at(@black_cards, i)
  end

  def id({:white, i}) do
    i
  end

  def id({:black, i}) do
    i
  end

  def deal_white do
    white_ids() |> Enum.shuffle()
  end

  def deal_black do
    black_ids() |> Enum.shuffle()
  end

  def black_spaces(card) do
    blanks = Regex.scan(~r/_+/, text(card)) |> length()
    max(blanks, 1)
  end

  def white_ids do
    Enum.map(0..(length(@white_cards) - 1), &{:white, &1})
  end

  def black_ids do
    Enum.map(0..(length(@black_cards) - 1), &{:black, &1})
  end
end
