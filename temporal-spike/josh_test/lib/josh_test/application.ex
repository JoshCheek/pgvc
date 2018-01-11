defmodule JoshTest.App do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      supervisor(JoshTest.Repo, [])
    ]

    opts = [strategy: :one_for_one, name: JoshTest.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

