module Network.Gossip.Helpers where

import qualified Control.Concurrent.Thread as Thread
import           Crypto.Hash
import qualified Data.ByteString           as B
import qualified Data.ByteString.Char8     as C
import           Data.Time.Clock.POSIX     (getPOSIXTime)

curTime :: IO Int
curTime = round `fmap` getPOSIXTime

customHash :: Show a => a -> B.ByteString
customHash x = C.pack $ show ((hash $ C.pack $ show x) :: Digest SHA3_512)

runThread :: IO () -> IO ()
runThread action = do
  (_, _) <- Thread.forkIO action
  return ()
