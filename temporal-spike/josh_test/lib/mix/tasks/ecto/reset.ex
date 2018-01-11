defmodule Mix.Tasks.Ecto.Reset do
  use Mix.Task

  @shortdoc "Reset the database"
  def run(_) do
    0 = sh "mix", ['ecto.drop']
    0 = sh "mix", ['ecto.create']
    0 = sh "mix", ['ecto.migrate']
  end

  defp sh(cmd, args) do
    IO.puts "\e[35m$ \e[34m#{cmd} \e[94m#{args}\e[0m"
    {printed, status} = System.cmd cmd, args
    IO.puts printed
    status
  end
end
