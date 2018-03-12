# gossip-haskell

This implements a very simple gossip protocol over an [Abstract Network](https://github.com/sakshamsharma/abstract-network). This should make developing distributed applications very easy, since it abstracts away all communication / peer-list / keep-alive / discovery-of-peers logics.

It will also not forward messages which have already been forwarded in the past (timestamping would be a good idea if you want to re-send a message).

## Important API

### createGossiper

You can create a Gossip Context as follows:
```
createGossiper :: UserNetContext IO -> [NetAddr] -> String -> (B.ByteString -> IO ()) ->
                  IO GossipContext
```

Arguments:
* A user network context (from [abstract-network](https://github.com/sakshamsharma/abstract-network)).
* A list of addresses of seed / bootstrap peers.
* An action to run on receiving an application message (this will not be called when keep-alive/discovery etc messages are received).

This GossipContext will be used for communication on the set-up network.

### doGossip

This action will send the input bytes over the whole network.
```
doGossip :: GossipContext -> B.ByteString -> IO ()
```

Arguments:
* GossipContext / Gossip Network, over which the message has to be sent.
* The bytes to be sent over the network.

## TODO
The project is functional, but some important functionality is missing.

* PeerSet does not send pings yet. A process must be launched which does this.
* PeerSet does not yet run a process to purge peers which have not responded in a while.
* PeerSet does not allow configuration of parameters yet.
* Peer Discovery messages are not being sent yet.
* We should allow configuring a predicate, which chooses whether a message needs to be forwarded. For example, some stale messages could be discarded.
