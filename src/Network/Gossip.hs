{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric  #-}

module Network.Gossip where

import           Control.Concurrent.STM      (atomically)
import           Control.Concurrent.STM.TVar
import           Control.Monad
import           Control.Monad.State.Strict
import qualified Data.ByteString             as B
import qualified Data.ByteString.Char8       as C
import qualified Data.HashSet                as S
import           Data.Serialize
import           GHC.Generics                (Generic)
import           Network.Abstract.Types      (NetAddr)
import           Network.Gossip.Context
import           Network.Gossip.Helpers
import           Network.Gossip.PeerSet
import           Prelude
import           Text.Read

data Msg = BytesMsg { bytes :: B.ByteString } |
           PingMsg |
           PingReplyMsg |
           DiscoverMsg
         deriving (Show, Read, Generic, Serialize)

gossipReceiver :: GossipContext -> B.ByteString -> NetAddr -> IO B.ByteString
gossipReceiver c msg frm =
  let m = read $ C.unpack msg
  in case m of
    BytesMsg _   -> recvGossipInternal c m frm >> return B.empty
    PingMsg      -> recvPing c frm >> return B.empty
    PingReplyMsg -> recvPingReply c frm >> return B.empty
    DiscoverMsg  -> recvDisc c frm

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

discoverNodes :: GossipContext -> IO ()
discoverNodes c = do
  let bytes = C.pack . show $ DiscoverMsg
  peers <- getPeersIO (peers c)
  responses <- mapM (\addr -> askPeer c addr bytes) peers
  mapM_ (updatePeers . C.unpack) responses
    where updatePeers resp =
            case readEither resp :: Either String [NetAddr] of
              Left err -> putStrLn "Invalid response for new nodes query"
              Right npeers -> do
                putStrLn $ "Informed about nodes " ++ show npeers
                mapM_ (markPeerAlive (peers c)) npeers

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
  mapM_ (\addr -> sendGossip c addr bytes) addrs
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
           BytesMsg b -> recvGossip c b
           _          -> return ()
    return ()

recvPing :: GossipContext -> NetAddr -> IO ()
recvPing c sender = do
  _ <- markPeerAlive (peers c) sender
  let bytes = C.pack $ show PingReplyMsg
  sendGossip c sender bytes

recvPingReply :: GossipContext -> NetAddr -> IO ()
recvPingReply c sender = liftIO $ markPeerAlive (peers c) sender

recvDisc :: GossipContext -> NetAddr -> IO B.ByteString
recvDisc c sender = do
  _ <- markPeerAlive (peers c) sender
  ps <- getPeersIO (peers c)
  let filteredPeers = filter (/= sender) ps
  return . C.pack . show $ filteredPeers
