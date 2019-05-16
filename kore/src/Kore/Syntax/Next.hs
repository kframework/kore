{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}

{-# LANGUAGE TemplateHaskell #-}

module Kore.Syntax.Next
    ( Next (..)
    ) where

import           Control.DeepSeq
                 ( NFData (..) )
import qualified Data.Deriving as Deriving
import           Data.Hashable
import qualified Data.Text.Prettyprint.Doc as Pretty
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Debug
import Kore.Sort
import Kore.Unparser

{-|'Next' corresponds to the @\next@ branch of the @object-pattern@
syntactic category from the Semantics of K, Section 9.1.4 (Patterns).

'nextSort' is both the sort of the operand and the sort of the result.

-}
data Next sort child = Next
    { nextSort  :: !sort
    , nextChild :: child
    }
    deriving (Eq, Functor, Foldable, GHC.Generic, Ord, Show, Traversable)

Deriving.deriveEq1 ''Next
Deriving.deriveOrd1 ''Next
Deriving.deriveShow1 ''Next

instance (Hashable sort, Hashable child) => Hashable (Next sort child)

instance (NFData sort, NFData child) => NFData (Next sort child)

instance SOP.Generic (Next sort child)

instance SOP.HasDatatypeInfo (Next sort child)

instance (Debug sort, Debug child) => Debug (Next sort child)

instance Unparse child => Unparse (Next Sort child) where
    unparse Next { nextSort, nextChild } =
        "\\next"
        <> parameters [nextSort]
        <> arguments [nextChild]

    unparse2 Next { nextChild } =
        Pretty.parens (Pretty.fillSep ["\\next", unparse2 nextChild])
