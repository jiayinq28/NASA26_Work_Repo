module Main where

import Language.Copilot (Stream, Word8, mux, true, false, extern, reify, arg, trigger, observer)
import Copilot.Compile.Bluespec (compile)

-- Instantiates the streams for the 8 switches on FPGA
sw0 :: Stream Bool 
sw0 = extern "sw0" Nothing

sw1 :: Stream Bool
sw1 = extern "sw1" Nothing

sw2 :: Stream Bool
sw2 = extern "sw2" Nothing

sw3 :: Stream Bool
sw3 = extern "sw3" Nothing

sw4 :: Stream Bool
sw4 = extern "sw4" Nothing

sw5 :: Stream Bool
sw5 = extern "sw5" Nothing

sw6 :: Stream Bool
sw6 = extern "sw6" Nothing

sw7 :: Stream Bool
sw7 = extern "sw7" Nothing

-- Instantiates the streams for the 8 LEDs on FPGA
led0 :: Stream Bool
led0 = sw0

led1 :: Stream Bool
led1 = sw1

led2 :: Stream Bool
led2 = sw2

led3 :: Stream Bool
led3 = sw3

led4 :: Stream Bool
led4 = sw4

led5 :: Stream Bool
led5 = sw5

led6 :: Stream Bool
led6 = sw6

led7 :: Stream Bool
led7 = sw7

-- Functions to make a list of Stream Bool to Stream Word8
boolToWord8 :: Stream Bool -> Stream Word8
boolToWord8 x = y
  where y = mux x 1 0
switches :: [Stream Word8]
switches = map boolToWord8 [sw7, sw6, sw5, sw4, sw3, sw2, sw1, sw0]

-- Function to make the list of 0,1 to its eq power of 2
switchesBitMask :: [Stream Word8]
switchesBitMask = zipWith (*) switches powersOfTwo
  where powersOfTwo = [128, 64, 32, 16, 8, 4, 2, 1]
arr :: [Stream Word8]
arr = switchesBitMask

-- Function to sum the list of powers of 2 to get the value
switchesSum :: Stream Word8
switchesSum = arr !! 0 + arr !! 1 + arr !! 2 + arr !! 3 
            + arr !! 4 + arr !! 5 + arr !! 6 + arr !! 7
            

spec = do
  trigger "led0" true [arg led0]
  trigger "led1" true [arg led1]
  trigger "led2" true [arg led2]
  trigger "led3" true [arg led3]
  trigger "led4" true [arg led4]
  trigger "led5" true [arg led5]
  trigger "led6" true [arg led6]
  trigger "led7" true [arg led7]
  trigger "switchesSum" true [arg switchesSum]

main = do
  spec' <- reify spec
  compile "SwVals" spec'