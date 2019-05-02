{-|
Module      : Kore.Domain.External
Description : Domain values in the concrete syntax of Kore
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : thomas.tuegel@runtimeverification.com
-}

{-# LANGUAGE TemplateHaskell #-}

module Kore.Domain.External
    ( External (..)
    , lensDomainValueSort
    , lensDomainValueChild
    , CommonExternalPattern
    , Domain (..)
    ) where

import Control.DeepSeq
       ( NFData )
import Data.Deriving
       ( deriveEq1, deriveOrd1, deriveShow1 )
import Data.Functor.Const
       ( Const )
import Data.Hashable
       ( Hashable )
import Data.Void
       ( Void )
import GHC.Generics
       ( Generic )

import Control.Lens.TH.Rules
       ( makeLenses )
import Kore.Domain.Class
import Kore.Syntax
import Kore.Unparser

data External child =
    External
        { domainValueSort :: Sort
        , domainValueChild :: CommonPattern (Const Void)
        }
    deriving (Eq, Foldable, Functor, Generic, Ord, Show, Traversable)

makeLenses ''External
deriveEq1 ''External
deriveOrd1 ''External
deriveShow1 ''External

instance Hashable (External child)

instance NFData (External child)

instance Unparse (External child) where
    unparse (External { domainValueSort, domainValueChild }) =
        "\\dv"
        <> parameters [domainValueSort]
        <> arguments [domainValueChild]
    unparse2 (External { domainValueSort, domainValueChild }) =
        "\\dv"
        <> parameters2 [domainValueSort]
        <> arguments2 [domainValueChild]

instance Domain External where
    lensDomainValue mapDomainValue external =
        getExternal <$> mapDomainValue original
      where
        original = DomainValue { domainValueSort, domainValueChild = external }
          where
            External { domainValueSort } = external
        getExternal
            :: forall child
            .  DomainValue Sort (External child)
            -> External child
        getExternal DomainValue { domainValueSort, domainValueChild } =
            domainValueChild { domainValueSort } :: External child

type CommonExternalPattern = CommonPattern External
