{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}

{-# LANGUAGE TemplateHaskell #-}

module Kore.Syntax.PatternF where

import           Control.DeepSeq
                 ( NFData (..) )
import qualified Data.Deriving as Deriving
import           Data.Functor.Classes
import           Data.Functor.Const
                 ( Const )
import           Data.Functor.Identity
                 ( Identity (..) )
import           Data.Hashable
import           Data.Void
                 ( Void )
import           GHC.Generics
                 ( Generic )

import Kore.Sort
import Kore.Syntax.And
import Kore.Syntax.Application
import Kore.Syntax.Bottom
import Kore.Syntax.Ceil
import Kore.Syntax.CharLiteral
import Kore.Syntax.Equals
import Kore.Syntax.Exists
import Kore.Syntax.Floor
import Kore.Syntax.Forall
import Kore.Syntax.Iff
import Kore.Syntax.Implies
import Kore.Syntax.In
import Kore.Syntax.Next
import Kore.Syntax.Not
import Kore.Syntax.Or
import Kore.Syntax.Rewrites
import Kore.Syntax.SetVariable
import Kore.Syntax.StringLiteral
import Kore.Syntax.Top
import Kore.Unparser

{- | 'Pattern' is a Kore pattern head.

-}
data Pattern domain variable child
    = AndPattern           !(And Sort child)
    | ApplicationPattern   !(Application SymbolOrAlias child)
    | BottomPattern        !(Bottom Sort child)
    | CeilPattern          !(Ceil Sort child)
    | DomainValuePattern   !(domain child)
    | EqualsPattern        !(Equals Sort child)
    | ExistsPattern        !(Exists Sort variable child)
    | FloorPattern         !(Floor Sort child)
    | ForallPattern        !(Forall Sort variable child)
    | IffPattern           !(Iff Sort child)
    | ImpliesPattern       !(Implies Sort child)
    | InPattern            !(In Sort child)
    | NextPattern          !(Next Sort child)
    | NotPattern           !(Not Sort child)
    | OrPattern            !(Or Sort child)
    | RewritesPattern      !(Rewrites Sort child)
    | StringLiteralPattern !StringLiteral
    | CharLiteralPattern   !CharLiteral
    | TopPattern           !(Top Sort child)
    | VariablePattern      !variable
    | InhabitantPattern    !Sort
    | SetVariablePattern   !(SetVariable variable)
    deriving (Foldable, Functor, Generic, Traversable)

Deriving.deriveEq1 ''Pattern
Deriving.deriveOrd1 ''Pattern
Deriving.deriveShow1 ''Pattern

instance
    (Eq1 domain, Eq variable, Eq child) =>
    Eq (Pattern domain variable child)
  where
    (==) = eq1
    {-# INLINE (==) #-}

instance
    (Ord1 domain, Ord variable, Ord child) =>
    Ord (Pattern domain variable child)
  where
    compare = compare1
    {-# INLINE compare #-}

instance
    (Show1 domain, Show variable, Show child) =>
    Show (Pattern domain variable child)
  where
    showsPrec = showsPrec1
    {-# INLINE showsPrec #-}

instance
    ( Hashable child
    , Hashable variable
    , Hashable (domain child)
    ) =>
    Hashable (Pattern domain variable child)

instance
    ( NFData child
    , NFData variable
    , NFData (domain child)
    ) =>
    NFData (Pattern domain variable child)

instance
    ( Unparse child
    , Unparse (domain child)
    , Unparse variable
    ) =>
    Unparse (Pattern domain variable child)
  where
    unparse =
        \case
            AndPattern p           -> unparse p
            ApplicationPattern p   -> unparse p
            BottomPattern p        -> unparse p
            CeilPattern p          -> unparse p
            DomainValuePattern p   -> unparse p
            EqualsPattern p        -> unparse p
            ExistsPattern p        -> unparse p
            FloorPattern p         -> unparse p
            ForallPattern p        -> unparse p
            IffPattern p           -> unparse p
            ImpliesPattern p       -> unparse p
            InPattern p            -> unparse p
            NextPattern p          -> unparse p
            NotPattern p           -> unparse p
            OrPattern p            -> unparse p
            RewritesPattern p      -> unparse p
            StringLiteralPattern p -> unparse p
            CharLiteralPattern p   -> unparse p
            TopPattern p           -> unparse p
            VariablePattern p      -> unparse p
            InhabitantPattern s          -> unparse s
            SetVariablePattern p   -> unparse p

    unparse2 =
        \case
            AndPattern p           -> unparse2 p
            ApplicationPattern p   -> unparse2 p
            BottomPattern p        -> unparse2 p
            CeilPattern p          -> unparse2 p
            DomainValuePattern p   -> unparse2 p
            EqualsPattern p        -> unparse2 p
            ExistsPattern p        -> unparse2 p
            FloorPattern p         -> unparse2 p
            ForallPattern p        -> unparse2 p
            IffPattern p           -> unparse2 p
            ImpliesPattern p       -> unparse2 p
            InPattern p            -> unparse2 p
            NextPattern p          -> unparse2 p
            NotPattern p           -> unparse2 p
            OrPattern p            -> unparse2 p
            RewritesPattern p      -> unparse2 p
            StringLiteralPattern p -> unparse2 p
            CharLiteralPattern p   -> unparse2 p
            TopPattern p           -> unparse2 p
            VariablePattern p      -> unparse2 p
            InhabitantPattern s          -> unparse s
            SetVariablePattern p   -> unparse p

{-|'dummySort' is used in error messages when we want to convert an
'UnsortedPatternStub' to a pattern that can be displayed.
-}
dummySort :: Sort
dummySort = SortVariableSort (SortVariable (noLocationId "dummy"))

{- | Use the provided mapping to replace all variables in a 'Pattern' head.

__Warning__: @mapVariables@ will capture variables if the provided mapping is
not injective!

-}
mapVariables
    :: (variable1 -> variable2)
    -> Pattern domain variable1 child
    -> Pattern domain variable2 child
mapVariables mapping =
    runIdentity . traverseVariables (Identity . mapping)
{-# INLINE mapVariables #-}

{- | Use the provided traversal to replace all variables in a 'Pattern' head.

__Warning__: @traverseVariables@ will capture variables if the provided
traversal is not injective!

-}
traverseVariables
    :: Applicative f
    => (variable1 -> f variable2)
    -> Pattern domain variable1 child
    -> f (Pattern domain variable2 child)
traverseVariables traversing =
    \case
        -- Non-trivial cases
        ExistsPattern any0 -> ExistsPattern <$> traverseVariablesExists any0
        ForallPattern all0 -> ForallPattern <$> traverseVariablesForall all0
        VariablePattern variable -> VariablePattern <$> traversing variable
        InhabitantPattern s -> pure (InhabitantPattern s)
        SetVariablePattern (SetVariable variable)
            -> SetVariablePattern . SetVariable <$> traversing variable
        -- Trivial cases
        AndPattern andP -> pure (AndPattern andP)
        ApplicationPattern appP -> pure (ApplicationPattern appP)
        BottomPattern botP -> pure (BottomPattern botP)
        CeilPattern ceilP -> pure (CeilPattern ceilP)
        DomainValuePattern dvP -> pure (DomainValuePattern dvP)
        EqualsPattern eqP -> pure (EqualsPattern eqP)
        FloorPattern flrP -> pure (FloorPattern flrP)
        IffPattern iffP -> pure (IffPattern iffP)
        ImpliesPattern impP -> pure (ImpliesPattern impP)
        InPattern inP -> pure (InPattern inP)
        NextPattern nxtP -> pure (NextPattern nxtP)
        NotPattern notP -> pure (NotPattern notP)
        OrPattern orP -> pure (OrPattern orP)
        RewritesPattern rewP -> pure (RewritesPattern rewP)
        StringLiteralPattern strP -> pure (StringLiteralPattern strP)
        CharLiteralPattern charP -> pure (CharLiteralPattern charP)
        TopPattern topP -> pure (TopPattern topP)
  where
    traverseVariablesExists Exists { existsSort, existsVariable, existsChild } =
        Exists existsSort <$> traversing existsVariable <*> pure existsChild
    traverseVariablesForall Forall { forallSort, forallVariable, forallChild } =
        Forall forallSort <$> traversing forallVariable <*> pure forallChild

-- | Use the provided mapping to replace all domain values in a 'Pattern' head.
mapDomainValues
    :: (forall child'. domain1 child' -> domain2 child')
    -> Pattern domain1 variable child
    -> Pattern domain2 variable child
mapDomainValues mapping =
    \case
        -- Non-trivial case
        DomainValuePattern domainP -> DomainValuePattern (mapping domainP)
        InhabitantPattern s -> InhabitantPattern s
        -- Trivial cases
        AndPattern andP -> AndPattern andP
        ApplicationPattern appP -> ApplicationPattern appP
        BottomPattern botP -> BottomPattern botP
        CeilPattern ceilP -> CeilPattern ceilP
        EqualsPattern eqP -> EqualsPattern eqP
        ExistsPattern existsP -> ExistsPattern existsP
        FloorPattern flrP -> FloorPattern flrP
        ForallPattern forallP -> ForallPattern forallP
        IffPattern iffP -> IffPattern iffP
        ImpliesPattern impP -> ImpliesPattern impP
        InPattern inP -> InPattern inP
        NextPattern nextP -> NextPattern nextP
        NotPattern notP -> NotPattern notP
        OrPattern orP -> OrPattern orP
        RewritesPattern rewP -> RewritesPattern rewP
        StringLiteralPattern strP -> StringLiteralPattern strP
        CharLiteralPattern charP -> CharLiteralPattern charP
        TopPattern topP -> TopPattern topP
        VariablePattern varP -> VariablePattern varP
        SetVariablePattern varP -> SetVariablePattern varP

{- | Cast a 'Pattern' head with @'Const' 'Void'@ domain values into any domain.

The @Const Void@ domain excludes domain values; the pattern head can be cast
trivially because it must contain no domain values.

 -}
castVoidDomainValues
    :: Pattern (Const Void) variable child
    -> Pattern domain       variable child
castVoidDomainValues = mapDomainValues (\case {})
