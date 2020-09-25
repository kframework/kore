{- |
Copyright   : (c) Runtime Verification, 2020
License     : NCSA

 -}

module Kore.Rewriting.RewritingVariable
    ( RewritingVariableName
    , RewritingVariable
    , isConfigVariable
    , isRuleVariable
    , isSomeConfigVariable
    , isSomeConfigVariableName
    , isSomeRuleVariable
    , isSomeRuleVariableName
    , isElementRuleVariable
    , isElementRuleVariableName
    , mkConfigVariable
    , mkRuleVariable
    , mkElementConfigVariable
    , mkElementRuleVariable
    , mkUnifiedRuleVariable
    , mkUnifiedConfigVariable
    , mkRewritingPattern
    , resetResultPattern
    , getRemainderPredicate
    , assertRemainderPattern
    , resetConfigVariable
    , getRewritingVariable
    -- * Exported for unparsing/testing
    , getRewritingPattern
    , getRewritingTerm
    ) where

import Prelude.Kore

import Control.DeepSeq
    ( NFData
    )
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Debug
import Kore.Attribute.Pattern.FreeVariables
    ( FreeVariables
    )
import qualified Kore.Attribute.Pattern.FreeVariables as FreeVariables
import Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( Predicate
    )
import qualified Kore.Internal.Predicate as Predicate
import qualified Kore.Internal.Substitution as Substitution
import Kore.Internal.TermLike as TermLike hiding
    ( refreshVariables
    )
import Kore.Unparser
import Kore.Variables.Fresh

{- | The name of a 'RewritingVariable'.
 -}
data RewritingVariableName
    = ConfigVariableName !VariableName
    | RuleVariableName   !VariableName
    deriving (Eq, Ord, Show)
    deriving (GHC.Generic)
    deriving anyclass (Hashable, NFData)
    deriving anyclass (SOP.Generic, SOP.HasDatatypeInfo)
    deriving anyclass (Debug, Diff)

instance SubstitutionOrd RewritingVariableName where
    compareSubstitution (RuleVariableName _) (ConfigVariableName _) = LT
    compareSubstitution (ConfigVariableName _) (RuleVariableName _) = GT
    compareSubstitution variable1 variable2 =
        on compareSubstitution toVariableName variable1 variable2

instance FreshPartialOrd RewritingVariableName where
    minBoundName =
        \case
            RuleVariableName var   -> RuleVariableName (minBoundName var)
            ConfigVariableName var -> ConfigVariableName (minBoundName var)
    {-# INLINE minBoundName #-}

    maxBoundName =
        \case
            RuleVariableName var   -> RuleVariableName (maxBoundName var)
            ConfigVariableName var -> ConfigVariableName (maxBoundName var)
    {-# INLINE maxBoundName #-}

    nextName (RuleVariableName name1) (RuleVariableName name2) =
        RuleVariableName <$> nextName name1 name2
    nextName (ConfigVariableName name1) (ConfigVariableName name2) =
        ConfigVariableName <$> nextName name1 name2
    nextName _ _ = Nothing
    {-# INLINE nextName #-}

instance Unparse RewritingVariableName where
    unparse (ConfigVariableName variable) = "Config" <> unparse variable
    unparse (RuleVariableName variable) = "Rule" <> unparse variable

    unparse2 (ConfigVariableName variable) = "Config" <> unparse2 variable
    unparse2 (RuleVariableName variable) = "Rule" <> unparse2 variable

instance From RewritingVariableName VariableName where
    from (ConfigVariableName variable) = variable
    from (RuleVariableName variable) = variable

instance From VariableName RewritingVariableName where
    from = RuleVariableName

instance FreshName RewritingVariableName

type RewritingVariable = Variable RewritingVariableName

mkElementConfigVariable
    :: ElementVariable VariableName
    -> ElementVariable RewritingVariableName
mkElementConfigVariable = (fmap . fmap) ConfigVariableName

mkElementRuleVariable
    :: ElementVariable VariableName
    -> ElementVariable RewritingVariableName
mkElementRuleVariable = (fmap . fmap) RuleVariableName

mkUnifiedRuleVariable
    :: SomeVariable VariableName
    -> SomeVariable RewritingVariableName
mkUnifiedRuleVariable = (fmap . fmap) RuleVariableName

mkUnifiedConfigVariable
    :: SomeVariable VariableName
    -> SomeVariable RewritingVariableName
mkUnifiedConfigVariable = (fmap . fmap) ConfigVariableName

getRuleVariable :: RewritingVariableName -> Maybe VariableName
getRuleVariable (RuleVariableName var) = Just var
getRuleVariable _ = Nothing

getUnifiedRuleVariable
    :: SomeVariable RewritingVariableName
    -> Maybe (SomeVariable VariableName)
getUnifiedRuleVariable = (traverse . traverse) getRuleVariable

-- | Unwrap every variable in the pattern. This is unsafe in
-- contexts related to unification. To be used only where the
-- rewriting information is not necessary anymore, such as
-- unparsing.
getRewritingPattern
    :: Pattern RewritingVariableName
    -> Pattern VariableName
getRewritingPattern = Pattern.mapVariables getRewritingVariable

-- | Unwrap every variable in the term. This is unsafe in
-- contexts related to unification. To be used only where the
-- rewriting information is not necessary anymore, such as
-- unparsing.
getRewritingTerm
    :: TermLike RewritingVariableName
    -> TermLike VariableName
getRewritingTerm = TermLike.mapVariables getRewritingVariable

resetConfigVariable
    :: AdjSomeVariableName
        (RewritingVariableName -> RewritingVariableName)
resetConfigVariable =
    pure (.) <*> pure mkConfigVariable <*> getRewritingVariable

getRewritingVariable
    :: AdjSomeVariableName (RewritingVariableName -> VariableName)
getRewritingVariable = pure (from @RewritingVariableName @VariableName)

mkConfigVariable :: VariableName -> RewritingVariableName
mkConfigVariable = ConfigVariableName

mkRuleVariable :: VariableName -> RewritingVariableName
mkRuleVariable = RuleVariableName

isConfigVariable :: RewritingVariableName -> Bool
isConfigVariable (ConfigVariableName _) = True
isConfigVariable _ = False

isRuleVariable :: RewritingVariableName -> Bool
isRuleVariable (RuleVariableName _) = True
isRuleVariable _ = False

-- | Safely reset all the variables in the pattern to configuration
-- variables.
resetResultPattern
    :: HasCallStack
    => FreeVariables RewritingVariableName
    -> Pattern RewritingVariableName
    -> Pattern RewritingVariableName
resetResultPattern initial config@Conditional { substitution } =
    Pattern.mapVariables resetConfigVariable renamed
  where
    substitution' = Substitution.filter isSomeConfigVariable substitution
    filtered = config { Pattern.substitution = substitution' }
    avoiding =
        initial
        & FreeVariables.toNames
        & (Set.map . fmap) toVariableName
    introduced =
        Set.fromAscList
        . mapMaybe getUnifiedRuleVariable
        . Set.toAscList
        . FreeVariables.toSet
        $ freeVariables filtered
    renaming =
        Map.mapKeys (fmap RuleVariableName)
        . Map.map (TermLike.mkVar . mkUnifiedConfigVariable)
        $ refreshVariables avoiding introduced
    renamed :: Pattern RewritingVariableName
    renamed = filtered & Pattern.substitute renaming

-- | Renames configuration variables to distinguish them from those in the rule.
mkRewritingPattern :: Pattern VariableName -> Pattern RewritingVariableName
mkRewritingPattern = Pattern.mapVariables (pure ConfigVariableName)

getRemainderPredicate
    :: Predicate RewritingVariableName
    -> Predicate VariableName
getRemainderPredicate predicate =
    Predicate.mapVariables getRewritingVariable predicate
    & assert (all isSomeConfigVariable freeVars)
  where
    freeVars = freeVariables predicate & FreeVariables.toList

assertRemainderPattern
    :: HasCallStack
    => Pattern RewritingVariableName
    -> Pattern RewritingVariableName
assertRemainderPattern pattern' =
    pattern'
    & assert (all isSomeConfigVariable freeVars)
  where
    freeVars = freeVariables pattern' & FreeVariables.toList

isSomeConfigVariable :: SomeVariable RewritingVariableName -> Bool
isSomeConfigVariable = isSomeConfigVariableName . variableName

isSomeConfigVariableName :: SomeVariableName RewritingVariableName -> Bool
isSomeConfigVariableName = foldSomeVariableName (pure isConfigVariable)

isSomeRuleVariable :: SomeVariable RewritingVariableName -> Bool
isSomeRuleVariable = isSomeRuleVariableName . variableName

isSomeRuleVariableName :: SomeVariableName RewritingVariableName -> Bool
isSomeRuleVariableName = foldSomeVariableName (pure isRuleVariable)

isElementRuleVariable :: ElementVariable RewritingVariableName -> Bool
isElementRuleVariable = isElementRuleVariableName . variableName

isElementRuleVariableName :: ElementVariableName RewritingVariableName -> Bool
isElementRuleVariableName = any isRuleVariable
