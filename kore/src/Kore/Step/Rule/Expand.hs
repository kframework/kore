{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
-}

module Kore.Step.Rule.Expand
    ( ExpandSingleConstructors (..)
    ) where

import Prelude.Kore

import Control.Lens
    ( (%=)
    )
import Control.Monad.State.Strict
    ( State
    , evalState
    )
import qualified Control.Monad.State.Strict as State
import qualified Data.Bifunctor as Bifunctor
import Data.Generics.Product
    ( field
    )
import Data.Map.Strict
    ( Map
    )
import qualified Data.Map.Strict as Map
import Data.Set
    ( Set
    )
import qualified Data.Set as Set
import qualified GHC.Generics as GHC

import qualified Debug
import Kore.Attribute.Pattern.FreeVariables
    ( freeVariables
    )
import qualified Kore.Attribute.Pattern.FreeVariables as FreeVariables
import qualified Kore.Attribute.Sort.Constructors as Attribute.Constructors
    ( Constructor (Constructor)
    , ConstructorLike (ConstructorLikeConstructor)
    , Constructors (Constructors)
    )
import qualified Kore.Attribute.Sort.Constructors as Constructors.DoNotUse
import Kore.IndexedModule.MetadataTools
    ( SmtMetadataTools
    , findSortConstructors
    )
import qualified Kore.Internal.Condition as Condition
import qualified Kore.Internal.OrPattern as OrPattern
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( makeAndPredicate
    )
import qualified Kore.Internal.Predicate as Predicate
import Kore.Internal.Substitution
    ( Substitution
    )
import qualified Kore.Internal.Substitution as Substitution
import Kore.Internal.TermLike
    ( InternalVariable
    , TermLike
    , mkApplySymbol
    , mkElemVar
    )
import qualified Kore.Internal.TermLike as TermLike
    ( substitute
    )
import Kore.Rewriting.RewritingVariable
    ( RewritingVariableName
    )
import Kore.Sort
    ( Sort (..)
    , SortActual (SortActual)
    )
import qualified Kore.Sort as Sort.DoNotUse
import qualified Kore.Step.AntiLeft as AntiLeft
    ( substitute
    )
import Kore.Step.ClaimPattern
    ( AllPathRule (..)
    , ClaimPattern (..)
    , OnePathRule (..)
    , ReachabilityRule (..)
    , freeVariablesLeft
    )
import Kore.Step.RulePattern
    ( RulePattern (RulePattern)
    )
import qualified Kore.Step.RulePattern as OLD
import Kore.Syntax.Variable
import Kore.Variables.Fresh
    ( refreshVariable
    )
import qualified Pretty

-- | Instantiate variables on sorts with a single constructor
{- TODO(ttuegel): make this a strategy step, so that we expand any
    single-constructor variables at the start of each proof step.
    Going even further: make this a step in the variable simplifier?
-}
class ExpandSingleConstructors rule where
    expandSingleConstructors
        :: SmtMetadataTools attributes
        -> rule
        -> rule

instance ExpandSingleConstructors (RulePattern VariableName) where
    expandSingleConstructors
        metadataTools
        rule@(RulePattern _ _ _ _ _)
      = case rule of
        RulePattern
            { left, antiLeft, requires
            , rhs = OLD.RHS {existentials, right, ensures}
            } ->
            let leftVariables :: [ElementVariable VariableName]
                leftVariables =
                    mapMaybe retractElementVariable
                    $ FreeVariables.toList
                    $ freeVariables left
                allSomeVariables :: Set (SomeVariable VariableName)
                allSomeVariables =
                    FreeVariables.toSet (freeVariables rule)
                allElementVariables :: Set (ElementVariableName VariableName)
                allElementVariables =
                    Set.fromList
                    $ map variableName
                    $ mapMaybe retract (Set.toList allSomeVariables)
                        ++ existentials
                expansion
                    ::  Map.Map
                            (SomeVariable VariableName)
                            (TermLike VariableName)
                expansion =
                    expandVariables
                        metadataTools
                        leftVariables
                        allElementVariables
                substitutionPredicate =
                    ( Substitution.toPredicate
                    . Substitution.wrap
                    . Substitution.mkUnwrappedSubstitution
                    )
                        (Map.toList expansion)
                subst = Map.mapKeys variableName expansion
            in rule
                { OLD.left = TermLike.substitute subst left
                , OLD.antiLeft =
                    AntiLeft.substitute subst <$> antiLeft
                , OLD.requires =
                    makeAndPredicate
                        (Predicate.substitute subst requires)
                        substitutionPredicate
                , OLD.rhs = OLD.RHS
                    { existentials
                    , right = TermLike.substitute subst right
                    , ensures = Predicate.substitute subst ensures
                    }
                }

instance ExpandSingleConstructors OLD.OnePathRule where
    expandSingleConstructors tools =
        OLD.OnePathRule . expandSingleConstructors tools . OLD.getOnePathRule

instance ExpandSingleConstructors OLD.AllPathRule where
    expandSingleConstructors tools =
        OLD.AllPathRule . expandSingleConstructors tools . OLD.getAllPathRule

instance ExpandSingleConstructors OLD.ReachabilityRule where
    expandSingleConstructors tools (OLD.OnePath rule) =
        OLD.OnePath
        . OLD.OnePathRule
        . expandSingleConstructors tools
        . OLD.getOnePathRule
        $ rule
    expandSingleConstructors tools (OLD.AllPath rule) =
        OLD.AllPath
        . OLD.AllPathRule
        . expandSingleConstructors tools
        . OLD.getAllPathRule
        $ rule

instance ExpandSingleConstructors ClaimPattern where
    expandSingleConstructors
        metadataTools
        rule@(ClaimPattern _ _ _ _)
      = case rule of
        ClaimPattern
            { left
            , existentials
            , right
            } ->
            let leftElementVariables
                    :: [ElementVariable RewritingVariableName]
                leftElementVariables =
                    extractFreeElementVariables
                    . freeVariablesLeft
                    $ rule
                freeElementVariables
                    :: [ElementVariable RewritingVariableName]
                freeElementVariables =
                    extractFreeElementVariables
                    . freeVariables
                    $ rule
                allElementVariableNames
                    :: Set (ElementVariableName RewritingVariableName)
                allElementVariableNames =
                    variableName <$> freeElementVariables <> existentials
                    & Set.fromList
                expansion
                    ::  Map.Map
                            (SomeVariable RewritingVariableName)
                            (TermLike RewritingVariableName)
                expansion =
                    expandVariables
                        metadataTools
                        leftElementVariables
                        allElementVariableNames
                substitutionPredicate =
                    Substitution.toPredicate
                    . from @(Map _ _) @(Substitution _)
                    $ expansion
                subst = Map.mapKeys variableName expansion
            in rule
                { left =
                    Pattern.andCondition
                        (Pattern.substitute subst left)
                        (Condition.fromPredicate substitutionPredicate)
                , existentials
                , right = OrPattern.substitute subst right
                }
      where
        extractFreeElementVariables =
            mapMaybe retractElementVariable
            . FreeVariables.toList

instance ExpandSingleConstructors OnePathRule where
    expandSingleConstructors tools =
        OnePathRule . expandSingleConstructors tools . getOnePathRule

instance ExpandSingleConstructors AllPathRule where
    expandSingleConstructors tools =
        AllPathRule . expandSingleConstructors tools . getAllPathRule

instance ExpandSingleConstructors ReachabilityRule where
    expandSingleConstructors tools (OnePath rule) =
        OnePath
        . OnePathRule
        . expandSingleConstructors tools
        . getOnePathRule
        $ rule
    expandSingleConstructors tools (AllPath rule) =
        AllPath
        . AllPathRule
        . expandSingleConstructors tools
        . getAllPathRule
        $ rule

newtype Expansion variable =
    Expansion { stale :: Set (ElementVariableName variable) }
    deriving (GHC.Generic)

type Expander variable = State (Expansion variable)

expandVariables
    :: forall variable attributes
    .  InternalVariable variable
    => SmtMetadataTools attributes
    -> [ElementVariable variable]
    -> Set (ElementVariableName variable)
    -> Map (SomeVariable variable) (TermLike variable)
expandVariables metadataTools variables stale =
    wither expandAddVariable variables
    & flip evalState Expansion { stale }
    & (map . Bifunctor.first) inject
    & Map.fromList
  where
    expandAddVariable
        ::  ElementVariable variable
        ->  Expander variable
                (Maybe (ElementVariable variable, TermLike variable))
    expandAddVariable variable = do
        term <- expandVariable metadataTools variable
        if mkElemVar variable == term
            then return Nothing
            else return $ Just (variable, term)

expandVariable
    :: forall variable attributes
    .  InternalVariable variable
    => SmtMetadataTools attributes
    -> ElementVariable variable
    -> Expander variable (TermLike variable)
expandVariable metadataTools variable@Variable { variableSort } =
    expandSort metadataTools variable UseDirectly variableSort

expandSort
    :: forall variable attributes
    .  InternalVariable variable
    => SmtMetadataTools attributes
    -> ElementVariable variable
    -> VariableUsage
    -> Sort
    -> Expander variable (TermLike variable)
expandSort metadataTools defaultVariable variableUsage sort =
    case findSingleConstructor sort of
        Just constructor ->
            expandConstructor metadataTools defaultVariable constructor
        Nothing ->
            maybeNewVariable defaultVariable sort variableUsage
  where
    findSingleConstructor (SortVariableSort _) = Nothing
    findSingleConstructor (SortActualSort SortActual { sortActualName }) = do
        Attribute.Constructors.Constructors ctors <-
            findSortConstructors metadataTools sortActualName
        ctorLikes <- ctors
        case ctorLikes of
            Attribute.Constructors.ConstructorLikeConstructor ctor :| [] ->
                Just ctor
            _ -> Nothing

expandConstructor
    :: forall variable attributes
    .  InternalVariable variable
    => SmtMetadataTools attributes
    -> ElementVariable variable
    -> Attribute.Constructors.Constructor
    -> Expander variable (TermLike variable)
expandConstructor
    metadataTools
    defaultVariable
    Attribute.Constructors.Constructor { name = symbol, sorts }
  =
    mkApplySymbol symbol <$> traverse expandChildSort sorts
  where
    expandChildSort :: Sort -> Expander variable (TermLike variable)
    expandChildSort = expandSort metadataTools defaultVariable UseAsPrototype

{-| Context: we have a TermLike that contains a variables, and we
attempt to expand them into constructor applications whenever that's possible.

We expand a variable by attempting to expand its sort into an unique
constructor application, and, recursively, the argument sorts of that
constructor.

This data type tells us how to use the initial variable that we are expanding
when we can't expand a sort, so we have to return a variable of that sort
instead.
-}
data VariableUsage =
    UseDirectly
    -- ^ We don't need to generate a new variable, we are at the top and
    -- we didn't manage to expand anything, so we can just reuse the
    -- variable in the original term as the sort's expansion (useful if we
    -- want to have prettier terms).
  | UseAsPrototype
    -- ^ We have expanded the initial sort at least once, so we need a variable
    -- somewhere in the middle of the expansion. We can't reuse the original
    -- variable, so we need to generate a new one based on it.

maybeNewVariable
    :: forall variable
    .  InternalVariable variable
    => HasCallStack
    => ElementVariable variable
    -> Sort
    -> VariableUsage
    -> Expander variable (TermLike variable)
maybeNewVariable
    variable@Variable { variableSort }
    sort
    UseDirectly
  =
    if sort /= variableSort
        then error "Unmatching sort for direct use variable."
        else pure (mkElemVar variable)
maybeNewVariable variable sort UseAsPrototype = do
    Expansion { stale } <- State.get
    case refreshVariable stale variable' of
        Just newVariable -> do
            field @"stale" %= Set.insert (variableName newVariable)
            pure (mkElemVar newVariable)
        Nothing ->
            (error . show . Pretty.hang 4 . Pretty.vsep)
                [ "Failed to generate a new name for:"
                , Pretty.indent 4 $ Debug.debug variable'
                , "while avoiding:"
                , Pretty.indent 4 $ Debug.debug stale
                ]
  where
    variable' = resort variable
    resort var = var { variableSort = sort }
