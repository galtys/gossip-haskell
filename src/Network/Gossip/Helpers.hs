module Network.Gossip.Helpers ( module Crypto.Hash
                              , curTime
                              , runThread
                              ) where

import qualified Control.Concurrent.Thread as Thread
import           Crypto.Hash
import qualified Data.ByteString           as B
import qualified Data.ByteString.Char8     as C
import           Data.Time.Clock.POSIX     (getPOSIXTime)

curTime :: IO Int
curTime = round `fmap` getPOSIXTime

runThread :: IO () -> IO ()
runThread action = do
  (_, _) <- Thread.forkIO action
  return ()
