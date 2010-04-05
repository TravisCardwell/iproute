module Data.IP.Addr where

import Control.Monad
import Data.Bits
import Data.Char
import Data.List (foldl')
import Data.Word
import Text.Parsec
import Text.Parsec.String
import Text.Printf

----------------------------------------------------------------
--
-- IP
--

-- This is host byte order
type IPv4Addr = Word32
type IPv6Addr = (Word32,Word32,Word32,Word32)

{-|
  The abstract data structure to express an IPv4 address.
  To create this, use 'toIPv4'. Or use 'read' @\"192.0.2.1\"@ :: 'IPv4', for example.
-}
newtype IPv4 = IPv4 IPv4Addr deriving (Eq, Ord)

{-|
  The abstract data structure to express an IPv6 address.
  To create this, use 'toIPv6'. Or use 'read' @\"2001:DB8::1\"@ :: 'IPv6', for example.
-}
newtype IPv6 = IPv6 IPv6Addr deriving (Eq, Ord)

----------------------------------------------------------------
--
-- Show
--

instance Show IPv4 where
    show = showIPv4

instance Show IPv6 where
    show = showIPv6

showIPv4 :: IPv4 -> String
showIPv4 (IPv4 a) = show4 a
    where
      remQuo x = (x `mod` 256, x `div` 256)
      show4 q = let (a4,q4) = remQuo q
                    (a3,q3) = remQuo q4
                    (a2,q2) = remQuo q3
                    (a1, _) = remQuo q2
                 in printf "%d.%d.%d.%d" a1 a2 a3 a4

showIPv6 :: IPv6 -> String
showIPv6 (IPv6 (a1,a2,a3,a4)) = show6 a1 ++ ":" ++ show6 a2 ++ ":" ++ show6 a3 ++ ":" ++ show6 a4
    where
      remQuo x = (x `mod` 65536, x `div` 65536)
      show6 q = let (r2,q2) = remQuo q
                    (r1, _) = remQuo q2
                in printf "%02x:%02x" r1 r2


----------------------------------------------------------------
--
-- IntToIP
--

{-|
  The 'toIPv4' function takes a list of 'Int' and returns 'IPv4'.
  For example, 'toIPv4' @[192,0,2,1]@.
-}
toIPv4 :: [Int] -> IPv4
toIPv4 = IPv4 . toWord32
    where
      toWord32 [a1,a2,a3,a4] = fromIntegral $ shift a1 24 + shift a2 16 + shift a3 8 + a4
      toWord32 _             = error "toWord32"

{-|
  The 'toIPv6' function takes a list of 'Int' and returns 'IPv6'.
  For example, 'toIPv6' @[0x2001,0xDB8,0,0,0,0,0,1]@.
-}
toIPv6 :: [Int] -> IPv6
toIPv6 ad = let [x1,x2,x3,x4] = map toWord32 $ split2 ad
            in IPv6 (x1,x2,x3,x4)
    where
      split2 [] = []
      split2 x  = take 2 x : split2 (drop 2 x)
      toWord32 [a1,a2] = fromIntegral $ shift a1 16 + a2
      toWord32 _             = error "toWord32"

----------------------------------------------------------------
--
-- Read
--

instance Read IPv4 where
    readsPrec _ = parseIPv4

instance Read IPv6 where
    readsPrec _ = parseIPv6

parseIPv4 :: String -> [(IPv4,String)]
parseIPv4 cs = case parse (adopt ipv4) "parseIPv4" cs of
                 Right a4 -> a4
                 Left  _  -> error "parseIPv4"

parseIPv6 :: String -> [(IPv6,String)]
parseIPv6 cs = case parse (adopt ipv6) "parseIPv6" cs of
                 Right a6 -> a6
                 Left  _  -> error "parseIPv6"

adopt :: Parser a -> Parser [(a,String)]
adopt p = do x <- p
             rest <- getInput
             return [(x, rest)]

----------------------------------------------------------------
--
-- IPv4 Parser
--

dig :: Parser Int
dig = do { char '0'; return 0 } <|>
      do n <- oneOf ['1'..'9']
         ns <- many digit
         let ms = map digitToInt (n:ns)
             ret = foldl' (\x y -> x * 10 + y) 0 ms
         return ret

ipv4 :: Parser IPv4
ipv4 = do
    as <- dig `sepBy1` (char '.')
    check as
    return $ toIPv4 as
  where
    test errmsg adr = when (adr < 0 || 255 < adr) (unexpected errmsg)
    check as = do let errmsg = "IPv4 adddress"
                  when (length as /= 4) (unexpected errmsg)
                  mapM_ (test errmsg) as

----------------------------------------------------------------
--
-- IPv6 Parser (RFC 4291)
--

hex :: Parser Int
hex = do ns <- many1 hexDigit
         check ns
         let ms = map digitToInt ns
             val = foldl' (\x y -> x * 16 + y) 0 ms
         return val
    where
      check ns = when (length ns > 4) (unexpected "IPv6 address -- more than 4 hex")

ipv6 :: Parser IPv6
ipv6 = do
    as <- ipv6'
    return $ toIPv6 as

ipv6' :: Parser [Int]
ipv6' =     do colon2
               bs <- option [] hexcolon
               rs <- format [] bs
               return rs
        <|> try (do rs <- hexcolon
                    check rs
                    return rs)
        <|> do bs1 <- hexcolon2
               bs2 <- option [] hexcolon
               rs <- format bs1 bs2
               return rs
    where
      colon2 = string "::"
      hexcolon = do bs <- hex `sepBy1` (char ':')
                    return bs
      hexcolon2 = do bs <- manyTill (do{ b <- hex; char ':'; return b }) (char ':')
                     return bs
      format bs1 bs2 = do let len1 = length bs1
                              len2 = length bs2
                          when (len1 > 7) (unexpected "IPv6 address")
                          when (len2 > 7) (unexpected "IPv6 address")
                          let len = 8 - len1 - len2
                          when (len <= 0) (unexpected "IPv6 address")
                          let spring = take len $ repeat 0
                          return $ bs1 ++ spring ++ bs2
      check bs = when (length bs /= 8) (unexpected "IPv6 address")

