{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}

module Kore.Syntax.StringLiteral
    ( StringLiteral (..)
    ) where

import           Control.DeepSeq
                 ( NFData (..) )
import           Data.Hashable
import           Data.Text
                 ( Text )
import qualified Data.Text.Prettyprint.Doc as Pretty
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Debug
import Kore.Unparser

{-|'StringLiteral' corresponds to the @string@ literal from the Semantics of K,
Section 9.1.1 (Lexicon).
-}
newtype StringLiteral = StringLiteral { getStringLiteral :: Text }
    deriving (Eq, GHC.Generic, Ord, Show)

instance Hashable StringLiteral

instance NFData StringLiteral

instance SOP.Generic StringLiteral

instance SOP.HasDatatypeInfo StringLiteral

instance Debug StringLiteral

instance Unparse StringLiteral where
    unparse = Pretty.dquotes . Pretty.pretty . escapeStringT . getStringLiteral
    unparse2 = unparse
