{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
 -}

module Kore.Builtin.Encoding
    ( encode8Bit
    , decode8Bit
    , parseBase16
    , toBase16
    ) where

import Prelude.Kore

import Control.Category
    ( (>>>)
    )
import qualified Data.Bits as Bits
import Data.ByteString
    ( ByteString
    )
import qualified Data.ByteString as ByteString
import Data.Char as Char
import qualified Data.List as List
import Data.Text
    ( Text
    )
import qualified Data.Text as Text
import Data.Vector.Unboxed
    ( Vector
    )
import qualified Data.Vector.Unboxed as Vector
import Data.Void
import Data.Word
    ( Word8
    )
import Text.Megaparsec
    ( Parsec
    )
import qualified Text.Megaparsec as Parsec

{- | Encode text using an 8-bit encoding.

Each 'Char' in the text is interpreted as a 'Data.Word.Word8'. It is an error if
any character falls outside that representable range.

 -}
encode8Bit :: Text -> ByteString
encode8Bit =
    Text.unpack
    >>> map (Char.ord >>> encodeByte)
    >>> ByteString.pack
  where
    encodeByte :: Int -> Word8
    encodeByte int
      | int < 0x00 = failed "expected positive value"
      | int > 0xFF = failed "expected 8-bit value"
      | otherwise = fromIntegral int
      where
        failed message =
            (error . unwords)
                [ "encode8Bit:"
                , message ++ ","
                , "found:"
                , show int
                ]

decode8Bit :: ByteString -> Text
decode8Bit =
    ByteString.unpack
    >>> map (Char.chr . fromIntegral)
    >>> Text.pack

parseBase16 :: Parsec Void Text ByteString
parseBase16 =
    parseByte <|> pure ByteString.empty
  where
    parseByte = do
        half1 <- toEnum . Char.digitToInt <$> Parsec.satisfy Char.isDigit
        half2 <- toEnum . Char.digitToInt <$> Parsec.satisfy Char.isDigit
        let byte = Bits.shiftL half1 4 Bits..|. half2
        ByteString.cons byte <$> parseBase16

toBase16 :: ByteString -> Text
toBase16 byteString =
    Text.pack . concat $ List.unfoldr unfold byteString
  where
    unfold bytes = do
        (byte, bytes') <- ByteString.uncons bytes
        let lo = byte Bits..&. 0x0F
            hi = Bits.shiftR byte 4
        pure ([encode hi, encode lo], bytes')
    encode half =
        assert (0 <= half && half < 16)
        $ (Vector.!) encodingBase16 (fromEnum half)

encodingBase16 :: Vector Char
encodingBase16 =
    Vector.fromList
        [ '0', '1', '2', '3', '4', '5', '6', '7'
        , '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
        ]
