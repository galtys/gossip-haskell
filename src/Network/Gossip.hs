{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric  #-}

module Network.Gossip where

import           Prelude

import           Control.Monad
import           Control.Monad.State.Strict

import           Control.Concurrent.Chan.Unagi
import           Control.Concurrent.STM        (atomically)
import           Control.Concurrent.STM.TVar

import qualified Data.ByteString               as B
import qualified Data.ByteString.Char8         as C
import qualified Data.HashSet                  as S
import           Data.Serialize

import           GHC.Generics                  (Generic)

import           Network.Gossip.Context
import           Network.Gossip.Helpers
import           Network.Gossip.PeerSet

import           Network.Abstract.Types

data Msg = BytesMsg { bytes :: B.ByteString } |
           PingMsg |
           PingReplyMsg |
           DiscoverMsg |
           DiscoverReplyMsg { newpeers :: [NetAddr] }
         deriving (Show, Read, Generic, Serialize)

createGossiper :: UserNetContext IO -> [NetAddr] -> String -> (B.ByteString -> IO ()) ->
                  IO GossipContext
createGossiper unc peers name_ dest = do
  ps_ <- newPeerSet peers -- Runs thread as well.
  smgss <- newTVarIO S.empty
  let gc = GossipContext { peers = ps_
                         , sentMsgs = smgss
                         , network = unc
                         , name = name_
                         , destination = dest
                         }
  _ <- runThread $ gossipListener gc
  return gc

runGossiper :: GossipContext -> IO ()
runGossiper gc = do
  _ <- runThread $ gossipListener gc
  return ()

gossipListener :: GossipContext -> IO ()
gossipListener gc = do
  let q = msgQueue (network gc)
  (from, msg_) <- readChan q
  let msg = read $ C.unpack msg_
  gossipReceiver gc msg from
  gossipListener gc

gossipReceiver :: GossipContext -> Msg -> NetAddr -> IO ()
gossipReceiver c m frm =
  case m of
    BytesMsg _         -> recvGossipInternal c m frm
    PingMsg            -> recvPing c frm
    PingReplyMsg       -> recvPingReply c frm
    DiscoverMsg        -> recvDisc c frm
    DiscoverReplyMsg x -> recvDiscReply c x frm

isItHandled :: TVar (S.HashSet B.ByteString) -> B.ByteString -> IO Bool
isItHandled sent msgSign =
  atomically $ do
    sentMsgs_ <- readTVar sent
    if S.member msgSign sentMsgs_ then return True
      else do
      _ <- modifyTVar sent $ S.insert msgSign
      return False

-- | doGossip gossips the given bytes to all neighboring peers.
doGossip :: GossipContext -> B.ByteString -> IO ()
doGossip c b = do
  sendto <- getPeersIO (peers c)
  _ <- isItHandled (sentMsgs c) (customHash b)
  sendGossipTo c (BytesMsg b) sendto

-- | forwardGossip forwards the given bytes to peers (except the sender of the bytes).
forwardGossip :: GossipContext -> Msg -> NetAddr -> IO ()
forwardGossip c d sender = do
  -- Sender doesn't need the message back.
  sendto <- filter (/= sender) <$> getPeersIO (peers c)
  sendGossipTo c d sendto

-- | sendGossipTo sends the given bytes to the provided addresses.
sendGossipTo :: GossipContext -> Msg -> [NetAddr] -> IO ()
sendGossipTo c d addrs = do
  let bytes = C.pack $ show d
  _ <- mapM (\addr -> sendMsg (network c) addr bytes) addrs
  return ()

-- | recvGossipInternal is invoked when some gossip is received on the network. It forwards
--   the gossip to neighbors after processing it.
recvGossipInternal :: GossipContext -> Msg -> NetAddr -> IO ()
recvGossipInternal c d sender = do
  handled <- isItHandled (sentMsgs c) (customHash d)
  unless handled $ do
    runThread $ forwardGossip c d sender
    addPeers (peers c) [sender]
    case d of
           BytesMsg b -> (destination c) b
           _          -> return ()
    return ()

recvPing :: GossipContext -> NetAddr -> IO ()
recvPing c sender = do
  _ <- markPeerAlive (peers c) sender
  let bytes = C.pack $ show PingReplyMsg
  sendMsg (network c) sender bytes

recvPingReply :: GossipContext -> NetAddr -> IO ()
recvPingReply c sender = liftIO $ markPeerAlive (peers c) sender

recvDisc :: GossipContext -> NetAddr -> IO ()
recvDisc c sender = do
  _ <- markPeerAlive (peers c) sender
  ps <- getPeersIO (peers c)
  let filteredPeers = filter (/= sender) ps
  let bytes = C.pack $ show (DiscoverReplyMsg [])
  sendMsg (network c) sender bytes

recvDiscReply :: GossipContext -> [NetAddr] -> NetAddr -> IO ()
recvDiscReply c npeers _ =
  mapM_ (\peer -> markPeerAlive (peers c) peer) npeers
