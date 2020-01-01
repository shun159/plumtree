defmodule Plumtree.Message do
  @moduledoc false

  @type gossip_t :: %{
          type: :gossip,
          mid: reference,
          payload: any,
          round: non_neg_integer,
          sender: Node.t(),
          origin: Node.t(),
          dont_fw: boolean
        }

  @type prune_t :: %{
          type: :prune,
          sender: Node.t()
        }

  @type ihave_t :: %{
          type: :ihave,
          sender: Node.t(),
          payload: any,
          mid: reference,
          round: non_neg_integer
        }

  @type graft_t :: %{
          type: :graft,
          sender: Node.t(),
          mid: reference,
          round: non_neg_integer
        }

  @spec gossip(reference, Node.t(), any, non_neg_integer) :: gossip_t
  def gossip(mid, payload, origin, round \\ 0) do
    %{
      type: :gossip,
      mid: mid,
      round: round,
      sender: Node.self(),
      origin: origin,
      payload: payload,
      dont_fw: false
    }
  end

  @spec ihave(reference, non_neg_integer) :: ihave_t
  def ihave(mid, round \\ 0) do
    %{
      type: :ihave,
      mid: mid,
      round: round,
      sender: Node.self()
    }
  end

  @spec prune() :: prune_t
  def prune do
    %{
      type: :prune,
      sender: Node.self()
    }
  end

  @spec graft(reference, non_neg_integer) :: graft_t
  def graft(mid, round) do
    %{
      type: :graft,
      sender: Node.self(),
      mid: mid,
      round: round
    }
  end
end
