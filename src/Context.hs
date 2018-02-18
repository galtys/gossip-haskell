module Context where

import           Prelude

import qualified Data.ByteString               as B
import qualified Data.HashSet                  as S

import           Control.Concurrent.Chan.Unagi
import           Control.Concurrent.STM.TVar

import           Network.Abstract.Types
import           PeerSet

data GossipContext = GossipContext { peers         :: PeerSet
                                   , sentMsgs      :: TVar (S.HashSet B.ByteString)
                                   , network       :: UserNetContext IO
                                   , name          :: String
                                   , gossipChan    :: OutChan B.ByteString
                                   , gossipAddChan :: InChan B.ByteString
                                   }
