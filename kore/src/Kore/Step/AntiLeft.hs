{-|
Copyright   : (c) Runtime Verification, 2020
License     : NCSA
-}

module Kore.Step.AntiLeft
    ( AntiLeft (..)
    , antiLeftPredicate
    , forgetSimplified
    , mapVariables
    , parse
    , substitute
    , toTermLike
    ) where

import Prelude.Kore

import Control.DeepSeq
    ( NFData
    )
import Data.Foldable
    ( fold
    , toList
    )
import Data.List
    ( foldl'
    )
import Data.Map
    ( Map
    )
import qualified Data.Map as Map
import Data.Set
    ( Set
    )
import qualified Data.Set as Set
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Debug
    ( Debug
    , Diff
    )
import Kore.Attribute.Pattern.FreeVariables
    ( HasFreeVariables (freeVariables)
    , bindVariables
    )
import qualified Kore.Attribute.Pattern.FreeVariables as FreeVariables
    ( toNames
    )
import Kore.Internal.Predicate
    ( Predicate
    , makeAndPredicate
    , makeCeilPredicate_
    , makeMultipleExists
    , makeMultipleOrPredicate
    , makeOrPredicate
    )
import qualified Kore.Internal.Predicate as Predicate
    ( forgetSimplified
    , mapVariables
    , substitute
    , wrapPredicate
    )
import Kore.Internal.TermLike
    ( pattern And_
    , pattern ApplyAlias_
    , pattern Bottom_
    , pattern Exists_
    , pattern Or_
    , TermLike
    , mkAnd
    , mkElemVar
    )
import qualified Kore.Internal.TermLike as TermLike
    ( forgetSimplified
    , mapVariables
    , substitute
    )
import Kore.Internal.Variable
    ( InternalVariable
    )
import Kore.Step.Simplification.ExpandAlias
    ( substituteInAlias
    )
import Kore.Syntax.Variable
    ( AdjSomeVariableName
    , ElementVariable
    , SomeVariableName (SomeVariableNameElement)
    , Variable (variableName)
    , mapElementVariable
    )
import Kore.Variables.Fresh
    ( FreshPartialOrd
    , refreshElementVariable
    )

data AntiLeftLhs variable = AntiLeftLhs
    { aliasTerm :: !(TermLike variable)
    , existentials :: ![ElementVariable variable]
    , predicate :: !(Predicate variable)
    , term :: !(TermLike variable)
    }
    deriving (GHC.Generic)

deriving instance Eq variable => Eq (AntiLeftLhs variable)
deriving instance Ord variable => Ord (AntiLeftLhs variable)
deriving instance Show variable => Show (AntiLeftLhs variable)

instance NFData variable => NFData (AntiLeftLhs variable)

instance SOP.Generic (AntiLeftLhs variable)

instance SOP.HasDatatypeInfo (AntiLeftLhs variable)

instance Debug variable => Debug (AntiLeftLhs variable)

instance (Debug variable, Diff variable) => Diff (AntiLeftLhs variable)

data AntiLeft variable = AntiLeft
    { aliasTerm :: !(TermLike variable)
    , maybeInner :: !(Maybe (AntiLeft variable))
    , leftHands :: ![AntiLeftLhs variable]
    }
    deriving (GHC.Generic)

deriving instance Eq variable => Eq (AntiLeft variable)
deriving instance Ord variable => Ord (AntiLeft variable)
deriving instance Show variable => Show (AntiLeft variable)

instance NFData variable => NFData (AntiLeft variable)

instance SOP.Generic (AntiLeft variable)

instance SOP.HasDatatypeInfo (AntiLeft variable)

instance Debug variable => Debug (AntiLeft variable)

instance (Debug variable, Diff variable) => Diff (AntiLeft variable)

instance
    InternalVariable variable
    => HasFreeVariables (AntiLeft variable) variable
  where
    freeVariables antiLeft@(AntiLeft _ _ _) = case antiLeft of
        AntiLeft { aliasTerm, maybeInner, leftHands } ->
            freeVariables aliasTerm
            <> fold
                (  toList (freeVariables <$> maybeInner)
                ++ map freeVariables leftHands
                )

instance
    InternalVariable variable
    => HasFreeVariables (AntiLeftLhs variable) variable
  where
    freeVariables antiLeft@(AntiLeftLhs _ _ _ _) = case antiLeft of
        AntiLeftLhs { aliasTerm, existentials, predicate, term } ->
            bindVariables
                (map (fmap SomeVariableNameElement) existentials)
                (  freeVariables predicate
                <> freeVariables term
                <> freeVariables aliasTerm
                )

mapVariables
    :: (Ord variable1, FreshPartialOrd variable2)
    => AdjSomeVariableName (variable1 -> variable2)
    -> AntiLeft variable1
    -> AntiLeft variable2
mapVariables adj antiLeft@(AntiLeft _ _ _) =
    case antiLeft of
        AntiLeft {aliasTerm, maybeInner, leftHands} ->
            AntiLeft
                { aliasTerm = TermLike.mapVariables adj aliasTerm
                , maybeInner = mapVariables adj <$> maybeInner
                , leftHands = map (mapVariablesLeft adj) leftHands
                }

mapVariablesLeft
    :: (Ord variable1, FreshPartialOrd variable2)
    => AdjSomeVariableName (variable1 -> variable2)
    -> AntiLeftLhs variable1
    -> AntiLeftLhs variable2
mapVariablesLeft adj antiLeft@(AntiLeftLhs _ _ _ _) =
    case antiLeft of
        AntiLeftLhs {aliasTerm, existentials, predicate, term} ->
            AntiLeftLhs
                { aliasTerm = TermLike.mapVariables adj aliasTerm
                , existentials = map (mapElementVariable adj) existentials
                , predicate = Predicate.mapVariables adj predicate
                , term = TermLike.mapVariables adj term
                }

substitute
    :: InternalVariable variable
    => Map (SomeVariableName variable) (TermLike variable)
    -> AntiLeft variable
    -> AntiLeft variable
substitute subst antiLeft@(AntiLeft _ _ _) =
    case antiLeft of
        AntiLeft {aliasTerm, maybeInner, leftHands} ->
            AntiLeft
                { aliasTerm = TermLike.substitute subst aliasTerm
                , maybeInner = substitute subst <$> maybeInner
                , leftHands = map (substituteLeft subst) leftHands
                }

substituteLeft
    :: InternalVariable variable
    => Map (SomeVariableName variable) (TermLike variable)
    -> AntiLeftLhs variable
    -> AntiLeftLhs variable
substituteLeft subst antiLeft@(AntiLeftLhs _ _ _ _) =
    case antiLeft of
        AntiLeftLhs {aliasTerm, existentials, predicate, term} ->
            AntiLeftLhs
                { aliasTerm = TermLike.substitute subst' aliasTerm
                , existentials
                , predicate = Predicate.substitute subst' predicate
                , term = TermLike.substitute subst' term
                }
          where
            subst' = foldl'
                (flip Map.delete)
                subst
                (map (SomeVariableNameElement . variableName) existentials)

forgetSimplified
    :: InternalVariable variable
    => AntiLeft variable
    -> AntiLeft variable
forgetSimplified antiLeft@(AntiLeft _ _ _) =
    case antiLeft of
        AntiLeft {aliasTerm, maybeInner, leftHands} ->
            AntiLeft
                { aliasTerm = TermLike.forgetSimplified aliasTerm
                , maybeInner = forgetSimplified <$> maybeInner
                , leftHands = map forgetSimplifiedLeft leftHands
                }

forgetSimplifiedLeft
    :: InternalVariable variable
    => AntiLeftLhs variable
    -> AntiLeftLhs variable
forgetSimplifiedLeft antiLeftLhs@(AntiLeftLhs _ _ _ _) = case antiLeftLhs of
    AntiLeftLhs {aliasTerm, existentials, predicate, term} ->
        AntiLeftLhs
            { aliasTerm = TermLike.forgetSimplified aliasTerm
            , existentials
            , predicate = Predicate.forgetSimplified predicate
            , term = TermLike.forgetSimplified term
            }

toTermLike :: AntiLeft variable -> TermLike variable
toTermLike AntiLeft {aliasTerm} = aliasTerm

{-
Supported syntax:
antiLeft = antiLeftAlias

The antiLeftAlias expands to
or(nextAntiLeft, or(lhs1, or(lhs2, ... or(lhsn, bottom) ... )))
where nextAntiLeft is optional.

nextAntileft has the same syntax as antiLeft.
lhs is of the form
exists x1 . exists x2 . ... exists xn . lhsTermAlias(x1, ..., xn)

lhsTermAlias expands to
and(lhsPredicate, lhsTerm)
-}
parse
    :: InternalVariable variable
    => TermLike variable -> Maybe (AntiLeft variable)
parse aliasTerm@(ApplyAlias_ alias params) = do
    (maybeInner, lhss) <-
        case substituteInAlias alias params of
            substituted@(Or_ _ first remaining) ->
                case parse first of
                    Just nextAntiLeft ->
                        Just (Just nextAntiLeft, remaining)
                    Nothing -> Just (Nothing, substituted)
            _ -> Nothing
    leftHands <- parseLhss lhss
    return AntiLeft {aliasTerm, maybeInner, leftHands}
parse _ = Nothing

parseLhss
    :: InternalVariable variable
    => TermLike variable -> Maybe [AntiLeftLhs variable]
parseLhss (Or_ _ first nexts) = do
    firstParsed <- parseLhs first
    nextsParsed <- parseLhss nexts
    return (firstParsed : nextsParsed)
parseLhss (Bottom_ _) = Just []
parseLhss _ = Nothing

parseLhs
    :: InternalVariable variable
    => TermLike variable
    -> Maybe (AntiLeftLhs variable)
parseLhs lhs = case aliasTerm of
    (ApplyAlias_ alias params) -> case (substituteInAlias alias params) of
        (And_ _ predicate term) ->
            Just AntiLeftLhs
                { aliasTerm
                , existentials
                , predicate = Predicate.wrapPredicate predicate
                , term
                }
        _ -> Nothing
    _ -> Nothing
  where
    (existentials, aliasTerm) = stripExistentials lhs

    stripExistentials
        :: TermLike variable -> ([ElementVariable variable], TermLike variable)
    stripExistentials (Exists_ _ var term) = (var : vars, remaining)
      where
        (vars, remaining) = stripExistentials term
    stripExistentials term = ([], term)

{-| Creates the AntiLeft predicate as described in
docs/2020-06-30-Combining-Priority-Axioms.md
-}
antiLeftPredicate
    :: InternalVariable variable
    => AntiLeft variable -> TermLike variable -> Predicate variable
antiLeftPredicate antiLeft@(AntiLeft _ _ _) term = case antiLeft of
    AntiLeft {maybeInner = Nothing, leftHands} ->
        antiLeftHandsPredicate leftHands term
    AntiLeft {maybeInner = Just inner, leftHands} ->
        makeOrPredicate
            (antiLeftPredicate inner term)
            (antiLeftHandsPredicate leftHands term)

antiLeftHandsPredicate
    :: forall variable . InternalVariable variable
    => [AntiLeftLhs variable] -> TermLike variable -> Predicate variable
antiLeftHandsPredicate antiLefts termLike =
    makeMultipleOrPredicate (map antiLeftHandPredicate antiLefts)
  where
    antiLeftHandPredicate :: AntiLeftLhs variable -> Predicate variable
    antiLeftHandPredicate antiLeftLhs@(AntiLeftLhs _ _ _ _) =
        case refreshedAntiLeftLhs of
            AntiLeftLhs {existentials, predicate, term} ->
                makeMultipleExists
                    existentials
                    (makeAndPredicate
                        predicate
                        (makeCeilPredicate_ (mkAnd termLike term))
                    )
      where
        used :: Set (SomeVariableName variable)
        used = FreeVariables.toNames (freeVariables termLike)

        refreshedAntiLeftLhs = refreshAntiLeftExistentials used antiLeftLhs

refreshAntiLeftExistentials
    :: forall variable
    .  InternalVariable variable
    => Set (SomeVariableName variable)
    -> AntiLeftLhs variable
    -> AntiLeftLhs variable
refreshAntiLeftExistentials
    alreadyUsed
    antiLeftLhs@(AntiLeftLhs {aliasTerm, existentials, predicate, term})
  = case antiLeftLhs of
    (AntiLeftLhs _ _ _ _) -> AntiLeftLhs
        { aliasTerm = TermLike.substitute substitution aliasTerm
        , existentials = map renameVar existentials
        , predicate = Predicate.substitute substitution predicate
        , term = TermLike.substitute substitution term
        }
  where
    refreshVariable
        :: Set (SomeVariableName variable)
        -> ElementVariable variable
        -> ElementVariable variable
    refreshVariable avoiding x =
        refreshElementVariable avoiding x & fromMaybe x

    refreshAndAvoid
        :: Set (SomeVariableName variable)
        -> ElementVariable variable
        -> (Set (SomeVariableName variable),  ElementVariable variable)
    refreshAndAvoid avoiding x =
        ( Set.insert (SomeVariableNameElement $ variableName refreshed) avoiding
        , refreshed
        )
      where refreshed = refreshVariable avoiding x

    refreshMap
        :: Set (SomeVariableName variable)
        -> [ElementVariable variable]
        -> Map (SomeVariableName variable) (ElementVariable variable)
    refreshMap _ [] = Map.empty
    refreshMap avoiding (var:vars) =
        Map.insert
            (SomeVariableNameElement $ variableName var)
            refreshedVar
            (refreshMap newAvoiding vars)
        where
        (newAvoiding, refreshedVar) = refreshAndAvoid avoiding var

    varSubstitution
        :: Map (SomeVariableName variable) (ElementVariable variable)
    varSubstitution = refreshMap alreadyUsed existentials

    substitution :: Map (SomeVariableName variable) (TermLike variable)
    substitution = fmap mkElemVar varSubstitution

    renameVar :: ElementVariable variable -> ElementVariable variable
    renameVar var = case Map.lookup someVariableName varSubstitution of
        Nothing -> var
        Just result -> result
      where
        someVariableName = SomeVariableNameElement (variableName var)
