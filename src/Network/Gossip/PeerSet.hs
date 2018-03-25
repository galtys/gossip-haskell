module Network.Gossip.PeerSet where

import           Prelude

import           Control.Concurrent          (threadDelay)
import           Control.Concurrent.STM      (atomically)
import           Control.Concurrent.STM.TVar
import           Control.Monad
import           Data.List                   ((\\))
import qualified Data.Map.Strict             as Map

import           Network.Abstract.Types
import           Network.Gossip.Helpers

pingDelay :: Int -- Seconds
pingDelay = 5

purgeDelay :: Int
purgeDelay = 4 * pingDelay

maxPeers :: Int
maxPeers = 10

newtype PeerSet = PeerSet (TVar (Map.Map NetAddr Int))

newPeerSet :: [NetAddr] -> IO PeerSet
newPeerSet ps = do
  v <- newTVarIO $ Map.fromList (zip ps (repeat 0))
  let res = PeerSet v
  _ <- runThread $ cleanPeers res -- TODO: Ignoring the threadID.
  return res

markPeerAlive :: PeerSet -> NetAddr -> IO ()
markPeerAlive (PeerSet ps) addr = do
  now <- curTime
  initSize <- Map.size <$> readTVarIO ps
  atomically $ modifyTVar ps $ addToMapIfPossible addr now
  finalSize <- Map.size <$> readTVarIO ps
  when (initSize /= finalSize) $ putStrLn $ "Possibly added node " ++ show addr

getPeersIO :: PeerSet -> IO [NetAddr]
getPeersIO (PeerSet ps) = Map.keys <$> readTVarIO ps

-- | cleanPeers periodically clears all processes which have not responded in a while.
cleanPeers :: PeerSet -> IO ()
cleanPeers peerSet@(PeerSet ps) = do
  _ <- threadDelay $ 6000000 * purgeDelay -- Every 1 minute.
  now <- curTime :: IO Int
  origPeers <- getPeersIO peerSet
  atomically $ modifyTVar ps $ Map.filter (\lastAlive -> purgeDelay + lastAlive < now)
  newPeers <- getPeersIO peerSet
  let diff = length $ origPeers \\ newPeers
  -- _ <- when (diff /= 0) $ putStrLn $ show diff ++ " peer(s) purged."
  cleanPeers peerSet

addPeers :: PeerSet -> [NetAddr] -> IO ()
addPeers (PeerSet ps) prs = do
  now <- curTime
  _ <- atomically $ mapM (\pr -> modifyTVar ps $ addToMapIfPossible pr now) prs
  return ()

addToMapIfPossible :: NetAddr -> Int -> Map.Map NetAddr Int -> Map.Map NetAddr Int
addToMapIfPossible addr now prs =
  if Map.size prs < maxPeers && not (Map.member addr prs) then
    Map.insert addr now prs
  else prs
