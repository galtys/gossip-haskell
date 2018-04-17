{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric  #-}

module Network.Gossip ( sayHiToAll
                      , gossipReceiver
                      , doGossip
                      , discoverNodes
                      , Network.Gossip.PeerSet.getPeersIO
                      ) where

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

sayHiToAll :: GossipContext -> IO ()
sayHiToAll c = do
  let d = PingMsg
  sendto <- getPeersIO (peers c)
  sendGossipTo c d sendto

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
  let msg = BytesMsg b
  _ <- isItHandled (sentMsgs c) (msgHash msg)
  sendGossipTo c msg sendto

discoverNodes :: GossipContext -> IO ()
discoverNodes c = do
  let bmsg = C.pack . show $ DiscoverMsg
  prs <- getPeersIO (peers c)
  responses <- mapM (\addr -> askPeer c addr bmsg) prs
  mapM_ (updatePeers . C.unpack) responses
    where updatePeers resp =
            case readEither resp :: Either String [NetAddr] of
              Left _ -> putStrLn $ "Invalid response for new nodes query: " ++ show resp
              Right npeers -> do
                putStrLn $ "Informed about nodes " ++ show npeers
                mapM_ (markPeerAlive (peers c)) npeers

-- | forwardGossip forwards the given bytes to peers (except the sender of the bytes).
forwardGossip :: GossipContext -> Msg -> NetAddr -> IO ()
forwardGossip c d sender = do
  -- Sender doesn't need the message back.
  sendto <- filter (/= sender) <$> getPeersIO (peers c)
  sendGossipTo c d sendto

-- | sendGossipTo sends the given message to the provided addresses.
sendGossipTo :: GossipContext -> Msg -> [NetAddr] -> IO ()
sendGossipTo c d = mapM_ $ sendMsgInternal c d

-- | sendMsgInternal sends given message to the provided address.
sendMsgInternal :: GossipContext -> Msg -> NetAddr -> IO ()
sendMsgInternal c d addr =
  let bmsg = C.pack $ show d
  in sendGossip c addr bmsg

-- | recvGossipInternal is invoked when some gossip is received on the network. It forwards
--   the gossip to neighbors after processing it.
recvGossipInternal :: GossipContext -> Msg -> NetAddr -> IO ()
recvGossipInternal c d sender = do
  handled <- isItHandled (sentMsgs c) (msgHash d)
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
  sendMsgInternal c PingReplyMsg sender

recvPingReply :: GossipContext -> NetAddr -> IO ()
recvPingReply c sender = liftIO $ markPeerAlive (peers c) sender

recvDisc :: GossipContext -> NetAddr -> IO B.ByteString
recvDisc c sender = do
  _ <- markPeerAlive (peers c) sender
  ps <- getPeersIO (peers c)
  let filteredPeers = filter (/= sender) ps
  return . C.pack . show $ filteredPeers

msgHash :: Msg -> B.ByteString
msgHash x = C.pack $ show ((hash $ C.pack $ show x) :: Digest SHA3_512)
