{-|
Module      : Kore.Domain.Builtin
Description : Internal representation of internal domains
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : thomas.tuegel@runtimeverification.com
-}

{-# LANGUAGE TemplateHaskell #-}

module Kore.Domain.Builtin
    ( Builtin (..)
    , Key
    , InternalMap (..)
    , lensBuiltinMapSort
    , lensBuiltinMapUnit
    , lensBuiltinMapElement
    , lensBuiltinMapConcat
    , lensBuiltinMapChild
    , InternalList (..)
    , lensBuiltinListSort
    , lensBuiltinListUnit
    , lensBuiltinListElement
    , lensBuiltinListConcat
    , lensBuiltinListChild
    , InternalSet (..)
    , lensBuiltinSetSort
    , lensBuiltinSetUnit
    , lensBuiltinSetElement
    , lensBuiltinSetConcat
    , lensBuiltinSetChild
    , InternalInt (..)
    , lensBuiltinIntSort
    , lensBuiltinIntValue
    , InternalBool (..)
    , lensBuiltinBoolSort
    , lensBuiltinBoolValue
    , module Kore.Domain.External
    , Domain (..)
    ) where

import           Control.DeepSeq
                 ( NFData (..) )
import           Data.Deriving
                 ( deriveEq1, deriveOrd1, deriveShow1 )
import qualified Data.Foldable as Foldable
import           Data.Functor.Classes
import           Data.Hashable
import           Data.Map
                 ( Map )
import qualified Data.Map as Map
import           Data.Sequence
                 ( Seq )
import           Data.Set
                 ( Set )
import qualified Data.Text.Prettyprint.Doc as Pretty
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Control.Lens.TH.Rules
       ( makeLenses )
import Kore.Domain.Class
import Kore.Domain.External
import Kore.Syntax
import Kore.Unparser

-- * Helpers

type Key = ConcretePattern Builtin

{- | Unparse a builtin collection type, given its symbols and children.

The children are already unparsed.

 -}
unparseCollection
    :: SymbolOrAlias  -- ^ unit symbol
    -> SymbolOrAlias  -- ^ element symbol
    -> SymbolOrAlias  -- ^ concat symbol
    -> [Pretty.Doc ann]      -- ^ children
    -> Pretty.Doc ann
unparseCollection unitSymbol elementSymbol concatSymbol builtinChildren =
    foldr applyConcat applyUnit (applyElement <$> builtinChildren)
  where
    applyUnit = unparse unitSymbol <> noArguments
    applyElement elem' = unparse elementSymbol <> elem'
    applyConcat set1 set2 = unparse concatSymbol <> arguments' [set1, set2]

-- * Builtin Map

{- | Internal representation of the builtin @MAP.Map@ domain.
 -}
data InternalMap child =
    InternalMap
        { builtinMapSort :: !Sort
        , builtinMapUnit :: !SymbolOrAlias
        , builtinMapElement :: !SymbolOrAlias
        , builtinMapConcat :: !SymbolOrAlias
        , builtinMapChild :: !(Map Key child)
        }
    deriving (Foldable, Functor, GHC.Generic, Traversable)

instance Eq child => Eq (InternalMap child) where
    (==) = eq1

instance Ord child => Ord (InternalMap child) where
    compare = compare1

instance Show child => Show (InternalMap child) where
    showsPrec = showsPrec1

instance Hashable child => Hashable (InternalMap child) where
    hashWithSalt salt builtin =
        hashWithSalt salt (Map.toAscList builtinMapChild)
      where
        InternalMap { builtinMapChild } = builtin

instance NFData child => NFData (InternalMap child)

instance Unparse child => Unparse (InternalMap child) where
    unparse builtinMap =
        unparseCollection
            builtinMapUnit
            builtinMapElement
            builtinMapConcat
            (unparseElementArguments <$> Map.toAscList builtinMapChild)
      where
        InternalMap { builtinMapChild } = builtinMap
        InternalMap { builtinMapUnit } = builtinMap
        InternalMap { builtinMapElement } = builtinMap
        InternalMap { builtinMapConcat } = builtinMap
        unparseElementArguments (key, value) =
            arguments' [unparse key, unparse value]

    unparse2 builtinMap =
        unparseCollection
            builtinMapUnit
            builtinMapElement
            builtinMapConcat
            (unparseElementArguments <$> Map.toAscList builtinMapChild)
      where
        InternalMap { builtinMapChild } = builtinMap
        InternalMap { builtinMapUnit } = builtinMap
        InternalMap { builtinMapElement } = builtinMap
        InternalMap { builtinMapConcat } = builtinMap
        unparseElementArguments (key, value) =
            arguments' [unparse2 key, unparse2 value]

-- * Builtin List

{- | Internal representation of the builtin @LIST.List@ domain.
 -}
data InternalList child =
    InternalList
        { builtinListSort :: !Sort
        , builtinListUnit :: !SymbolOrAlias
        , builtinListElement :: !SymbolOrAlias
        , builtinListConcat :: !SymbolOrAlias
        , builtinListChild :: !(Seq child)
        }
    deriving (Foldable, Functor, GHC.Generic, Traversable)

instance Eq child => Eq (InternalList child) where
    (==) = eq1

instance Ord child => Ord (InternalList child) where
    compare = compare1

instance Show child => Show (InternalList child) where
    showsPrec = showsPrec1

instance Hashable child => Hashable (InternalList child) where
    hashWithSalt salt builtin =
        hashWithSalt salt (Foldable.toList builtinListChild)
      where
        InternalList { builtinListChild } = builtin

instance NFData child => NFData (InternalList child)

instance Unparse child => Unparse (InternalList child) where
    unparse builtinList =
        unparseCollection
            builtinListUnit
            builtinListElement
            builtinListConcat
            (argument' . unparse <$> Foldable.toList builtinListChild)
      where
        InternalList { builtinListChild } = builtinList
        InternalList { builtinListUnit } = builtinList
        InternalList { builtinListElement } = builtinList
        InternalList { builtinListConcat } = builtinList

    unparse2 builtinList =
        unparseCollection
            builtinListUnit
            builtinListElement
            builtinListConcat
            (argument' . unparse2 <$> Foldable.toList builtinListChild)
      where
        InternalList { builtinListChild } = builtinList
        InternalList { builtinListUnit } = builtinList
        InternalList { builtinListElement } = builtinList
        InternalList { builtinListConcat } = builtinList

-- * Builtin Set

{- | Internal representation of the builtin @SET.Set@ domain.
 -}
data InternalSet =
    InternalSet
        { builtinSetSort :: !Sort
        , builtinSetUnit :: !SymbolOrAlias
        , builtinSetElement :: !SymbolOrAlias
        , builtinSetConcat :: !SymbolOrAlias
        , builtinSetChild :: !(Set Key)
        }
    deriving GHC.Generic

instance Hashable InternalSet where
    hashWithSalt salt builtin =
        hashWithSalt salt (Foldable.toList builtinSetChild)
      where
        InternalSet { builtinSetChild } = builtin

instance NFData InternalSet

instance Unparse InternalSet where
    unparse builtinSet =
        unparseCollection
            builtinSetUnit
            builtinSetElement
            builtinSetConcat
            (argument' . unparse <$> Foldable.toList builtinSetChild)
      where
        InternalSet { builtinSetChild } = builtinSet
        InternalSet { builtinSetUnit } = builtinSet
        InternalSet { builtinSetElement } = builtinSet
        InternalSet { builtinSetConcat } = builtinSet

    unparse2 builtinSet =
        unparseCollection
            builtinSetUnit
            builtinSetElement
            builtinSetConcat
            (argument' . unparse2 <$> Foldable.toList builtinSetChild)
      where
        InternalSet { builtinSetChild } = builtinSet
        InternalSet { builtinSetUnit } = builtinSet
        InternalSet { builtinSetElement } = builtinSet
        InternalSet { builtinSetConcat } = builtinSet

-- * Builtin Int

{- | Internal representation of the builtin @INT.Int@ domain.
 -}
data InternalInt =
    InternalInt
        { builtinIntSort :: !Sort
        , builtinIntValue :: !Integer
        }
    deriving (Eq, GHC.Generic, Ord, Show)

instance Hashable InternalInt

instance NFData InternalInt

instance Unparse InternalInt where
    unparse InternalInt { builtinIntSort, builtinIntValue } =
        "\\dv"
        <> parameters [builtinIntSort]
        <> arguments' [Pretty.dquotes $ Pretty.pretty builtinIntValue]

    unparse2 InternalInt { builtinIntSort, builtinIntValue } =
        "\\dv2"
        <> parameters2 [builtinIntSort]
        <> arguments' [Pretty.dquotes $ Pretty.pretty builtinIntValue]

-- * Builtin Bool

{- | Internal representation of the builtin @BOOL.Bool@ domain.
 -}
data InternalBool =
    InternalBool
        { builtinBoolSort :: !Sort
        , builtinBoolValue :: !Bool
        }
    deriving (Eq, GHC.Generic, Ord, Show)

instance Hashable InternalBool

instance NFData InternalBool

instance Unparse InternalBool where
    unparse InternalBool { builtinBoolSort, builtinBoolValue } =
        "\\dv"
        <> parameters [builtinBoolSort]
        <> arguments' [Pretty.dquotes value]
      where
        value
          | builtinBoolValue = "true"
          | otherwise        = "false"

    unparse2 InternalBool { builtinBoolSort, builtinBoolValue } =
        "\\dv2"
        <> parameters2 [builtinBoolSort]
        <> arguments' [Pretty.dquotes value]
      where
        value
          | builtinBoolValue = "true"
          | otherwise        = "false"

-- * Builtin domain representations

data Builtin child
    = BuiltinExternal !(External child)
    | BuiltinMap !(InternalMap child)
    | BuiltinList !(InternalList child)
    | BuiltinSet !InternalSet
    | BuiltinInt !InternalInt
    | BuiltinBool !InternalBool
    deriving (Foldable, Functor, GHC.Generic, Traversable)

deriving instance Eq child => Eq (Builtin child)

deriving instance Ord child => Ord (Builtin child)

deriving instance Show child => Show (Builtin child)

instance SOP.Generic (Builtin child)

instance Hashable child => Hashable (Builtin child)

instance NFData child => NFData (Builtin child)

instance Unparse child => Unparse (Builtin child) where
    unparse = unparseGeneric
    unparse2 = unparse2Generic

makeLenses ''InternalMap
makeLenses ''InternalList
makeLenses ''InternalSet
makeLenses ''InternalInt
makeLenses ''InternalBool

instance Domain Builtin where
    lensDomainValue mapDomainValue builtin =
        getBuiltin <$> mapDomainValue original
      where
        original =
            DomainValue
                { domainValueChild = builtin
                , domainValueSort = originalSort
                }
        originalSort =
            case builtin of
                BuiltinExternal External { domainValueSort } -> domainValueSort
                BuiltinInt InternalInt { builtinIntSort } -> builtinIntSort
                BuiltinBool InternalBool { builtinBoolSort } -> builtinBoolSort
                BuiltinMap InternalMap { builtinMapSort } -> builtinMapSort
                BuiltinList InternalList { builtinListSort } -> builtinListSort
                BuiltinSet InternalSet { builtinSetSort } -> builtinSetSort
        getBuiltin
            :: forall child
            .  DomainValue Sort (Builtin child)
            -> Builtin child
        getBuiltin DomainValue { domainValueSort, domainValueChild } =
            case domainValueChild of
                BuiltinExternal external ->
                    BuiltinExternal
                        (external { domainValueSort } :: External child)
                BuiltinInt internal ->
                    BuiltinInt internal { builtinIntSort = domainValueSort }
                BuiltinBool internal ->
                    BuiltinBool internal { builtinBoolSort = domainValueSort }
                BuiltinMap internal ->
                    BuiltinMap internal { builtinMapSort = domainValueSort }
                BuiltinList internal ->
                    BuiltinList internal { builtinListSort = domainValueSort }
                BuiltinSet internal ->
                    BuiltinSet internal { builtinSetSort = domainValueSort }

deriveEq1 ''InternalMap
deriveOrd1 ''InternalMap
deriveShow1 ''InternalMap

deriveEq1 ''InternalList
deriveOrd1 ''InternalList
deriveShow1 ''InternalList

deriveEq1 ''Builtin
deriveOrd1 ''Builtin
deriveShow1 ''Builtin

deriving instance Eq InternalSet
deriving instance Ord InternalSet
deriving instance Show InternalSet
