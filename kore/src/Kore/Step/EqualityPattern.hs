{-|
Description : Equality rules
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}
module Kore.Step.EqualityPattern
    ( EqualityPattern (..)
    , EqualityRule (..)
    , equalityPattern
    , equalityRuleToTerm
    , isSimplificationRule
    , getPriorityOfRule
    ) where

import Prelude.Kore

import Control.DeepSeq
    ( NFData
    )
import qualified Data.Default as Default
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Data.Text.Prettyprint.Doc
    ( Pretty
    )
import qualified Data.Text.Prettyprint.Doc as Pretty
import qualified Kore.Attribute.Axiom as Attribute
import Kore.Attribute.Pattern.FreeVariables
    ( HasFreeVariables (..)
    )
import qualified Kore.Attribute.Pattern.FreeVariables as FreeVariables
import Kore.Debug
import Kore.Equation
    ( Equation
    )
import qualified Kore.Equation as Equation
import Kore.Internal.Predicate
    ( Predicate
    )
import qualified Kore.Internal.Predicate as Predicate
import Kore.Internal.Symbol
    ( Symbol (..)
    )
import qualified Kore.Internal.TermLike as TermLike
import Kore.Internal.Variable
    ( InternalVariable
    , Variable
    )
import Kore.Step.Step
    ( InstantiationFailure (..)
    , UnifyingRule (..)
    )
import Kore.TopBottom
    ( TopBottom (..)
    )
import Kore.Unparser
    ( Unparse
    , unparse
    , unparse2
    )
import qualified Kore.Variables.Fresh as Fresh
import Kore.Variables.UnifiedVariable
    ( UnifiedVariable (..)
    )
import qualified Pretty
import qualified SQL

{- | Function axioms

 -}
data EqualityPattern variable = EqualityPattern
    { requires :: !(Predicate variable)
    , left  :: !(TermLike.TermLike variable)
    , right :: !(TermLike.TermLike variable)
    , ensures :: !(Predicate variable)
    , attributes :: !(Attribute.Axiom Symbol variable)
    }
    deriving (Eq, Ord, Show)
    deriving (GHC.Generic)

instance NFData variable => NFData (EqualityPattern variable)

instance SOP.Generic (EqualityPattern variable)

instance SOP.HasDatatypeInfo (EqualityPattern variable)

instance Debug variable => Debug (EqualityPattern variable)

instance (Debug variable, Diff variable) => Diff (EqualityPattern variable)

instance InternalVariable variable => Pretty (EqualityPattern variable) where
    pretty rulePattern'@(EqualityPattern _ _ _ _ _) =
        Pretty.vsep
            [ "requires:"
            , Pretty.indent 4 (unparse requires)
            , "left:"
            , Pretty.indent 4 (unparse left)
            , "right:"
            , Pretty.indent 4 (unparse right)
            , "ensures:"
            , Pretty.indent 4 (unparse ensures)
            ]
      where
        EqualityPattern
            { requires
            , left
            , right
            , ensures
            } = rulePattern'

instance TopBottom (EqualityPattern variable) where
    isTop _ = False
    isBottom _ = False

instance SQL.Table (EqualityPattern Variable)

instance SQL.Column (EqualityPattern Variable)
  where
    defineColumn = SQL.defineForeignKeyColumn
    toColumn = SQL.toForeignKeyColumn

instance From (Equation variable) (EqualityPattern variable) where
    from equation@(Equation.Equation _ _ _ _ _) =
        EqualityPattern { requires, left, right, ensures, attributes }
      where
        Equation.Equation { requires, left, right, ensures, attributes } =
            equation

instance From (EqualityPattern variable) (Equation variable) where
    from equation@(EqualityPattern _ _ _ _ _) =
        Equation.Equation { requires, left, right, ensures, attributes }
      where
        EqualityPattern { requires, left, right, ensures, attributes } =
            equation

-- | Creates a basic, unconstrained, Equality pattern
equalityPattern
    :: InternalVariable variable
    => TermLike.TermLike variable
    -> TermLike.TermLike variable
    -> EqualityPattern variable
equalityPattern left right =
    EqualityPattern
        { left
        , requires = Predicate.makeTruePredicate_
        , right
        , ensures = Predicate.makeTruePredicate_
        , attributes = Default.def
        }

{-  | Equality-based rule pattern.
-}
newtype EqualityRule variable =
    EqualityRule { getEqualityRule :: EqualityPattern variable }
    deriving (Eq, GHC.Generic, Ord, Show)

instance NFData variable => NFData (EqualityRule variable)

instance SOP.Generic (EqualityRule variable)

instance SOP.HasDatatypeInfo (EqualityRule variable)

instance Debug variable => Debug (EqualityRule variable)

instance (Debug variable, Diff variable) => Diff (EqualityRule variable)

instance
    InternalVariable variable
    => Unparse (EqualityRule variable)
  where
    unparse = unparse . equalityRuleToTerm
    unparse2 = unparse2 . equalityRuleToTerm

instance
    InternalVariable variable
    => HasFreeVariables (EqualityRule variable) variable
  where
    freeVariables (EqualityRule equality) = freeVariables equality

instance InternalVariable variable => SQL.Column (EqualityRule variable) where
    defineColumn = SQL.defineTextColumn
    toColumn = SQL.toColumn . Pretty.renderText . Pretty.layoutOneLine . unparse

instance From (EqualityRule variable) (EqualityPattern variable) where
    from = getEqualityRule

instance From (EqualityPattern variable) (EqualityRule variable)  where
    from = EqualityRule

instance From (Equation variable) (EqualityRule variable) where
    from = from @(EqualityPattern variable) . from @(Equation variable)

instance From (EqualityRule variable) (Equation variable) where
    from = from @(EqualityPattern variable) . from @(EqualityRule variable)

{-| Reverses an 'EqualityRule' back into its 'Pattern' representation.
  Should be the inverse of 'Rule.termToAxiomPattern'.
-}
equalityRuleToTerm
    :: InternalVariable variable
    => EqualityRule variable
    -> TermLike.TermLike variable
equalityRuleToTerm
     (EqualityRule
        (EqualityPattern
            Predicate.PredicateTrue
            left@(TermLike.Ceil_ _ resultSort1 _)
            (TermLike.Top_ resultSort2)
            Predicate.PredicateTrue
            _
        )
    )
  | resultSort1 == resultSort2 = left

equalityRuleToTerm
    (EqualityRule
        (EqualityPattern
            Predicate.PredicateTrue
            left
            right
            Predicate.PredicateTrue
            _
        )
    )
  =
    TermLike.mkEquals_ left right

equalityRuleToTerm
    (EqualityRule (EqualityPattern requires left right ensures _))
  =
    TermLike.mkImplies
        (Predicate.unwrapPredicate requires)
        (TermLike.mkAnd
            (TermLike.mkEquals_ left right)
            (Predicate.unwrapPredicate ensures)
        )

instance UnifyingRule EqualityPattern where
    mapRuleVariables mapElemVar mapSetVar rule1@(EqualityPattern _ _ _ _ _) =
        rule1
            { requires = mapPredicateVariables requires
            , left = mapTermLikeVariables left
            , right = mapTermLikeVariables right
            , ensures = mapPredicateVariables ensures
            , attributes =
                Attribute.mapAxiomVariables mapElemVar mapSetVar attributes
            }
      where
        EqualityPattern { requires, left, right, ensures, attributes } = rule1
        mapTermLikeVariables = TermLike.mapVariables mapElemVar mapSetVar
        mapPredicateVariables = Predicate.mapVariables mapElemVar mapSetVar

    matchingPattern = left

    precondition = requires

    refreshRule
        (FreeVariables.getFreeVariables -> avoid)
        rule1@(EqualityPattern _ _ _ _ _)
      =
        let rename = Fresh.refreshVariables avoid originalFreeVariables
            mapElemVars elemVar = case Map.lookup (ElemVar elemVar) rename of
                Just (ElemVar elemVar') -> elemVar'
                _ -> elemVar
            mapSetVars setVar = case Map.lookup (SetVar setVar) rename of
                Just (SetVar setVar') -> setVar'
                _ -> setVar
            subst = TermLike.mkVar <$> rename
            left' = TermLike.substitute subst left
            requires' = Predicate.substitute subst requires
            right' = TermLike.substitute subst right
            ensures' = Predicate.substitute subst ensures
            attributes' =
                Attribute.mapAxiomVariables mapElemVars mapSetVars attributes
            rule2 =
                rule1
                    { left = left'
                    , requires = requires'
                    , right = right'
                    , ensures = ensures'
                    , attributes = attributes'
                    }
        in (rename, rule2)
      where
        EqualityPattern { left, requires, right, ensures, attributes } = rule1
        originalFreeVariables =
            FreeVariables.getFreeVariables
            $ freeVariables rule1

    checkInstantiation
        rule
        substitutionMap
      = notConcretes ++ notSymbolics
      where
        attrs = attributes rule
        concretes = FreeVariables.getFreeVariables
            . Attribute.unConcrete . Attribute.concrete $ attrs
        symbolics = FreeVariables.getFreeVariables
            . Attribute.unSymbolic . Attribute.symbolic $ attrs
        checkConcrete var = case Map.lookup var substitutionMap of
            Nothing -> Just (UninstantiatedConcrete var)
            Just t ->
                if TermLike.isConstructorLike t
                    then Nothing
                    else Just (ConcreteFailure var t)
        checkSymbolic var = case Map.lookup var substitutionMap of
            Nothing -> Just (UninstantiatedSymbolic var)
            Just t ->
                if not(TermLike.isConstructorLike t)
                    then Nothing
                    else Just (SymbolicFailure var t)
        notConcretes = mapMaybe checkConcrete (Set.toList concretes)
        notSymbolics = mapMaybe checkSymbolic (Set.toList symbolics)

instance
    InternalVariable variable
    => HasFreeVariables (EqualityPattern variable) variable
  where
    freeVariables rule@(EqualityPattern _ _ _ _ _) = case rule of
        EqualityPattern { left, requires, right, ensures } ->
            freeVariables left
            <> freeVariables requires
            <> freeVariables right
            <> freeVariables ensures

isSimplificationRule :: EqualityRule variable -> Bool
isSimplificationRule (EqualityRule EqualityPattern { attributes }) =
    isSimplification
  where
    Attribute.Simplification { isSimplification } =
        Attribute.simplification attributes

getPriorityOfRule :: EqualityRule variable -> Integer
getPriorityOfRule = Attribute.getPriorityOfAxiom . attributes . getEqualityRule
