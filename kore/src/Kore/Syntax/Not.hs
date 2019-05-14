{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}

{-# LANGUAGE TemplateHaskell #-}

module Kore.Syntax.Not
    ( Not (..)
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

{-|'Not' corresponds to the @\not@ branches of the @object-pattern@ and
@meta-pattern@ syntactic categories from the Semantics of K,
Section 9.1.4 (Patterns).

'notSort' is both the sort of the operand and the sort of the result.

-}
data Not sort child = Not
    { notSort  :: !sort
    , notChild :: child
    }
    deriving (Eq, Functor, Foldable, GHC.Generic, Ord, Show, Traversable)

Deriving.deriveEq1 ''Not
Deriving.deriveOrd1 ''Not
Deriving.deriveShow1 ''Not

instance (Hashable sort, Hashable child) => Hashable (Not sort child)

instance (NFData sort, NFData child) => NFData (Not sort child)

instance SOP.Generic (Not sort child)

instance SOP.HasDatatypeInfo (Not sort child)

instance (Debug sort, Debug child) => Debug (Not sort child)

instance Unparse child => Unparse (Not Sort child) where
    unparse Not { notSort, notChild } =
        "\\not"
        <> parameters [notSort]
        <> arguments [notChild]

    unparse2 Not { notChild } =
        Pretty.parens (Pretty.fillSep ["\\not", unparse2 notChild])
