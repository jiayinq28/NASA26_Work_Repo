module Main where

import qualified Prelude as P ((++))
import Language.Copilot 
import Copilot.Compile.Bluespec (compile)

-- generate the 8 switch streams 
switches :: [Stream Bool]
switches = [extern ("sw" P.++ show i) Nothing | i <- [0..7]]

-- convert and sum the bits into a single Word8 stream
switchesSum :: Stream Word8
switchesSum = foldl1 (+) (zipWith (\sw pw -> mux sw pw 0) switches powers)
  where
    powers :: [Stream Word8]
    powers = [1, 2, 4, 8, 16, 32, 64, 128]

spec :: Spec
spec = do
  trigger "switchesSum" true [arg switchesSum]

main :: IO ()
main = reify spec >>= compile "SwValsBetter"