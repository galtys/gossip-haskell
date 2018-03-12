module Network.Gossip.Context where

import           Prelude

import qualified Data.ByteString               as B
import qualified Data.HashSet                  as S

import           Control.Concurrent.Chan.Unagi
import           Control.Concurrent.STM.TVar

import           Network.Abstract.Types
import           Network.Gossip.PeerSet

data GossipContext = GossipContext { peers         :: PeerSet
                                   , sentMsgs      :: TVar (S.HashSet B.ByteString)
                                   , network       :: UserNetContext IO
                                   , name          :: String
                                   , destination   :: B.ByteString -> IO ()
                                   }
