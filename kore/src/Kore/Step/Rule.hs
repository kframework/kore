{-|
Description : Rewrite and equality rules
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

-}

module Kore.Step.Rule
    ( EqualityRule (..)
    , RewriteRule (..)
    , OnePathRule (..)
    , AllPathRule (..)
    , ImplicationRule (..)
    , RulePattern (..)
    , rulePattern
    , isHeatingRule
    , isCoolingRule
    , isNormalRule
    , QualifiedAxiomPattern (..)
    , AxiomPatternError (..)
    , fromSentenceAxiom
    , fromSentence
    , extractRewriteAxioms
    , extractOnePathClaims
    , extractAllPathClaims
    , extractImplicationClaims
    , mkRewriteAxiom
    , mkEqualityAxiom
    , refreshRulePattern
    , freeVariables
    , Kore.Step.Rule.mapVariables
    , substitute
    ) where
import           Control.Comonad
import qualified Data.Default as Default
import           Data.Map.Strict
                 ( Map )
import           Data.Maybe
import           Data.Set
                 ( Set )
import qualified Data.Set as Set
import           Data.Text.Prettyprint.Doc
                 ( Pretty )
import qualified Data.Text.Prettyprint.Doc as Pretty

import           Kore.AST.Pure
import           Kore.AST.Sentence
import           Kore.AST.Valid hiding
                 ( freeVariables )
import qualified Kore.AST.Valid as Valid
import qualified Kore.Attribute.Axiom as Attribute
import qualified Kore.Attribute.Parser as Attribute.Parser
import           Kore.Error
import           Kore.IndexedModule.IndexedModule
import           Kore.Predicate.Predicate
                 ( Predicate )
import qualified Kore.Predicate.Predicate as Predicate
import           Kore.Step.TermLike
                 ( TermLike )
import qualified Kore.Step.TermLike as TermLike
import           Kore.Unparser
                 ( Unparse, unparse, unparse2 )
import           Kore.Variables.Fresh
import qualified Kore.Verified as Verified

newtype AxiomPatternError = AxiomPatternError ()

{- | Normal rewriting and function axioms, claims and patterns.

 -}
data RulePattern level variable = RulePattern
    { left  :: !(TermLike variable)
    , right :: !(TermLike variable)
    , requires :: !(Predicate variable)
    , ensures :: !(Predicate variable)
    , attributes :: !Attribute.Axiom
    }

deriving instance Eq variable => Eq (RulePattern level variable)
deriving instance Ord variable => Ord (RulePattern level variable)
deriving instance Show variable => Show (RulePattern level variable)

instance Unparse variable => Pretty (RulePattern level variable) where
    pretty rulePattern'@(RulePattern _ _ _ _ _) =
        Pretty.vsep
            [ "left:"
            , Pretty.indent 4 (unparse left)
            , "right:"
            , Pretty.indent 4 (unparse right)
            , "requires:"
            , Pretty.indent 4 (unparse requires)
            , "ensures:"
            , Pretty.indent 4 (unparse ensures)
            ]
      where
        RulePattern { left, right, requires, ensures } = rulePattern'

rulePattern
    :: TermLike variable
    -> TermLike variable
    -> RulePattern Object variable
rulePattern left right =
    RulePattern
        { left
        , right
        , requires = Predicate.makeTruePredicate
        , ensures  = Predicate.makeTruePredicate
        , attributes = Default.def
        }

{-  | Equality-based rule pattern.
-}
newtype EqualityRule level variable =
    EqualityRule { getEqualityRule :: RulePattern level variable }

deriving instance Eq variable => Eq (EqualityRule level variable)
deriving instance Ord variable => Ord (EqualityRule level variable)
deriving instance Show variable => Show (EqualityRule level variable)

{-  | Rewrite-based rule pattern.
-}
newtype RewriteRule level variable =
    RewriteRule { getRewriteRule :: RulePattern level variable }

deriving instance Eq variable => Eq (RewriteRule level variable)
deriving instance Ord variable => Ord (RewriteRule level variable)
deriving instance Show variable => Show (RewriteRule level variable)

instance (Unparse variable, Ord variable) => Unparse (RewriteRule level variable) where
    unparse (RewriteRule RulePattern { left, right, requires } ) =
        unparse
            $ Valid.mkImplies
                (Valid.mkAnd left (Predicate.unwrapPredicate requires))
                right
    unparse2 (RewriteRule RulePattern { left, right, requires } ) =
        unparse2
            $ Valid.mkImplies
                (Valid.mkAnd left (Predicate.unwrapPredicate requires))
                right

{-  | Implication-based pattern.
-}
newtype ImplicationRule level variable =
    ImplicationRule { getImplicationRule :: RulePattern level variable }

deriving instance Eq variable => Eq (ImplicationRule level variable)
deriving instance Ord variable => Ord (ImplicationRule level variable)
deriving instance Show variable => Show (ImplicationRule level variable)

qualifiedAxiomOpToConstructor
    :: SymbolOrAlias Object
    -> Maybe
        (RulePattern Object variable -> QualifiedAxiomPattern Object variable)
qualifiedAxiomOpToConstructor patternHead = case headName of
    "weakExistsFinally" -> Just $ OnePathClaimPattern . OnePathRule
    "weakAlwaysFinally" -> Just $ AllPathClaimPattern . AllPathRule
    _ -> Nothing
  where
    headName = getId (symbolOrAliasConstructor patternHead)

{-  | One-Path-Claim rule pattern.
-}
newtype OnePathRule level variable =
    OnePathRule { getOnePathRule :: RulePattern level variable }

deriving instance Eq variable => Eq (OnePathRule level variable)
deriving instance Ord variable => Ord (OnePathRule level variable)
deriving instance Show variable => Show (OnePathRule level variable)

{-  | All-Path-Claim rule pattern.
-}
newtype AllPathRule level variable =
    AllPathRule { getAllPathRule :: RulePattern level variable }

deriving instance Eq variable => Eq (AllPathRule level variable)
deriving instance Ord variable => Ord (AllPathRule level variable)
deriving instance Show variable => Show (AllPathRule level variable)

{- | Sum type to distinguish rewrite axioms (used for stepping)
from function axioms (used for functional simplification).
--}
data QualifiedAxiomPattern level variable
    = RewriteAxiomPattern (RewriteRule level variable)
    | FunctionAxiomPattern (EqualityRule level variable)
    | OnePathClaimPattern (OnePathRule level variable)
    | AllPathClaimPattern (AllPathRule level variable)
    | ImplicationAxiomPattern (ImplicationRule level variable)
    -- TODO(virgil): Rename the above since it applies to all sorts of axioms,
    -- not only to function-related ones.

deriving instance Eq variable => Eq (QualifiedAxiomPattern level variable)
deriving instance Ord variable => Ord (QualifiedAxiomPattern level variable)
deriving instance Show variable => Show (QualifiedAxiomPattern level variable)

{- | Does the axiom pattern represent a heating rule?
 -}
isHeatingRule :: RulePattern Object variable -> Bool
isHeatingRule RulePattern { attributes } =
    case Attribute.heatCool attributes of
        Attribute.Heat -> True
        _ -> False

{- | Does the axiom pattern represent a cooling rule?
 -}
isCoolingRule :: RulePattern Object variable -> Bool
isCoolingRule RulePattern { attributes } =
    case Attribute.heatCool attributes of
        Attribute.Cool -> True
        _ -> False

{- | Does the axiom pattern represent a normal rule?
 -}
isNormalRule :: RulePattern Object variable -> Bool
isNormalRule RulePattern { attributes } =
    case Attribute.heatCool attributes of
        Attribute.Normal -> True
        _ -> False


-- | Extracts all 'RewriteRule' axioms from a 'VerifiedModule'.
extractRewriteAxioms
    :: VerifiedModule declAtts axiomAtts
    -> [RewriteRule Object Variable]
extractRewriteAxioms idxMod =
    mapMaybe (extractRewriteAxiomFrom. getIndexedSentence)
        (indexedModuleAxioms idxMod)

extractRewriteAxiomFrom
    :: Verified.SentenceAxiom
    -- ^ Sentence to extract axiom pattern from
    -> Maybe (RewriteRule Object Variable)
extractRewriteAxiomFrom sentence =
    case fromSentenceAxiom sentence of
        Right (RewriteAxiomPattern axiomPat) -> Just axiomPat
        _ -> Nothing

-- | Extracts all One-Path claims from a verified module.
extractOnePathClaims
    :: VerifiedModule declAtts axiomAtts
    -- ^'IndexedModule' containing the definition
    -> [(axiomAtts, OnePathRule Object Variable)]
extractOnePathClaims idxMod =
    mapMaybe
        ( sequence                             -- (a, Maybe b) -> Maybe (a,b)
        . fmap extractOnePathClaimFrom         -- applying on second component
        )
    $ (indexedModuleClaims idxMod)

extractOnePathClaimFrom
    :: Verified.SentenceAxiom
    -- ^ Sentence to extract axiom pattern from
    -> Maybe (OnePathRule Object Variable)
extractOnePathClaimFrom sentence =
    case fromSentenceAxiom sentence of
        Right (OnePathClaimPattern claim) -> Just claim
        _ -> Nothing

-- | Extracts all All-Path claims from a verified definition.
extractAllPathClaims
    :: VerifiedModule declAtts axiomAtts
    -- ^'IndexedModule' containing the definition
    -> [(axiomAtts, AllPathRule Object Variable)]
extractAllPathClaims idxMod =
    mapMaybe
        ( sequence                             -- (a, Maybe b) -> Maybe (a,b)
        . fmap extractAllPathClaimFrom         -- applying on second component
        )
    (indexedModuleClaims idxMod)

extractAllPathClaimFrom
    :: Verified.SentenceAxiom
    -- ^ Sentence to extract axiom pattern from
    -> Maybe (AllPathRule Object Variable)
extractAllPathClaimFrom sentence =
    case fromSentenceAxiom sentence of
        Right (AllPathClaimPattern claim) -> Just claim
        _ -> Nothing

-- | Extract all 'ImplicationRule' claims matching a given @level@ from
-- a verified definition.
extractImplicationClaims
    :: VerifiedModule declAtts axiomAtts
    -- ^'IndexedModule' containing the definition
    -> [(axiomAtts, ImplicationRule Object Variable)]
extractImplicationClaims idxMod =
    mapMaybe
        ( sequence                               -- (a, Maybe b) -> Maybe (a,b)
        . fmap extractImplicationClaimFrom       -- applying on second component
        )
    $ (indexedModuleClaims idxMod)

extractImplicationClaimFrom
    :: Verified.SentenceAxiom
    -- ^ Sentence to extract axiom pattern from
    -> Maybe (ImplicationRule Object Variable)
extractImplicationClaimFrom sentence =
    case fromSentenceAxiom sentence of
        Right (ImplicationAxiomPattern axiomPat) -> Just axiomPat
        _ -> Nothing

-- | Attempts to extract a rule from the 'Verified.Sentence'.
fromSentence
    :: Verified.Sentence
    -> Either (Error AxiomPatternError) (QualifiedAxiomPattern Object Variable)
fromSentence (SentenceAxiomSentence sentenceAxiom) =
    fromSentenceAxiom sentenceAxiom
fromSentence _ =
    koreFail "Only axiom sentences can be translated to rules"

-- | Attempts to extract a rule from the 'Verified.SentenceAxiom'.
fromSentenceAxiom
    :: Verified.SentenceAxiom
    -> Either (Error AxiomPatternError) (QualifiedAxiomPattern Object Variable)
fromSentenceAxiom sentenceAxiom = do
    attributes <-
        (Attribute.Parser.liftParser . Attribute.Parser.parseAttributes)
            (sentenceAxiomAttributes sentenceAxiom)
    patternToAxiomPattern attributes (sentenceAxiomPattern sentenceAxiom)

{- | Match a pure pattern encoding an 'QualifiedAxiomPattern'.

@patternToAxiomPattern@ returns an error if the given 'CommonPurePattern' does
not encode a normal rewrite or function axiom.
-}
patternToAxiomPattern
    :: Attribute.Axiom
    -> TermLike Variable
    -> Either (Error AxiomPatternError) (QualifiedAxiomPattern Object Variable)
patternToAxiomPattern attributes pat =
    case pat of
        -- normal rewrite axioms
        -- TODO (thomas.tuegel): Allow \and{_}(ensures, rhs) to be wrapped in
        -- quantifiers.
        Rewrites_ _ (And_ _ requires lhs) (And_ _ ensures rhs) ->
            pure $ RewriteAxiomPattern $ RewriteRule RulePattern
                { left = lhs
                , right = rhs
                , requires = Predicate.wrapPredicate requires
                , ensures = Predicate.wrapPredicate ensures
                , attributes
                }
        -- Reachability claims
        Implies_ _ (And_ _ requires lhs) (App_ op [And_ _ ensures rhs])
          | Just constructor <- qualifiedAxiomOpToConstructor op ->
            pure $ constructor RulePattern
                { left = lhs
                , right = rhs
                , requires = Predicate.wrapPredicate requires
                , ensures = Predicate.wrapPredicate ensures
                , attributes
                }
        -- function axioms: general
        Implies_ _ requires (And_ _ (Equals_ _ _ lhs rhs) _ensures) ->
            -- TODO (traiansf): ensure that _ensures is \top
            pure $ FunctionAxiomPattern $ EqualityRule RulePattern
                { left = lhs
                , right = rhs
                , requires = Predicate.wrapPredicate requires
                , ensures = Predicate.makeTruePredicate
                , attributes
                }
        -- function axioms: trivial pre- and post-conditions
        Equals_ _ _ lhs rhs ->
            pure $ FunctionAxiomPattern $ EqualityRule RulePattern
                { left = lhs
                , right = rhs
                , requires = Predicate.makeTruePredicate
                , ensures = Predicate.makeTruePredicate
                , attributes
                }
        Forall_ _ _ child -> patternToAxiomPattern attributes child
        -- implication axioms:
        -- init -> modal_op ( prop )
        Implies_ _ lhs rhs@(App_ SymbolOrAlias { symbolOrAliasConstructor } _)
            | isModalSymbol symbolOrAliasConstructor ->
                pure $ ImplicationAxiomPattern $ ImplicationRule RulePattern
                    { left = lhs
                    , right = rhs
                    , requires = Predicate.makeTruePredicate
                    , ensures = Predicate.makeTruePredicate
                    , attributes
                    }
        _ -> koreFail "Unsupported pattern type in axiom"
      where
        isModalSymbol symbol =
            case getId symbol of
                "ag" -> True
                "ef" -> True
                _  -> False

{- | Construct a 'VerifiedKoreSentence' corresponding to 'RewriteRule'.

The requires clause must be a predicate, i.e. it can occur in any sort.

 -}
mkRewriteAxiom
    :: TermLike Variable  -- ^ left-hand side
    -> TermLike Variable  -- ^ right-hand side
    -> Maybe (Sort -> TermLike Variable)  -- ^ requires clause
    -> Verified.Sentence
mkRewriteAxiom lhs rhs requires =
    (SentenceAxiomSentence . mkAxiom_)
        (mkRewrites
            (mkAnd (fromMaybe mkTop requires $ patternSort) lhs)
            (mkAnd (mkTop patternSort) rhs)
        )
  where
    Valid { patternSort } = extract lhs

{- | Construct a 'VerifiedKoreSentence' corresponding to 'EqualityRule'.

The requires clause must be a predicate, i.e. it can occur in any sort.

 -}
mkEqualityAxiom
    :: TermLike Variable  -- ^ left-hand side
    -> TermLike Variable  -- ^ right-hand side
    -> Maybe (Sort -> TermLike Variable)  -- ^ requires clause
    -> Verified.Sentence
mkEqualityAxiom lhs rhs requires =
    SentenceAxiomSentence
    $ mkAxiom [sortVariableR]
    $ case requires of
        Just requires' ->
            mkImplies (requires' sortR) (mkAnd function mkTop_)
        Nothing -> function
  where
    sortVariableR = SortVariable "R"
    sortR = SortVariableSort sortVariableR
    function = mkEquals sortR lhs rhs

{- | Refresh the variables of a 'RulePattern'.

The free variables of a 'RulePattern' are implicitly quantified, so are renamed
to avoid collision with any variables in the given set.

 -}
refreshRulePattern
    :: forall variable
    .   ( FreshVariable variable
        , SortedVariable variable
        )
    => Set variable  -- ^ Variables to avoid
    -> RulePattern Object variable
    -> (Map variable variable, RulePattern Object variable)
refreshRulePattern avoid rule1 =
    let rename = refreshVariables avoid originalFreeVariables
        subst = mkVar <$> rename
        left' = TermLike.substitute subst left
        right' = TermLike.substitute subst right
        requires' = Predicate.substitute subst requires
        rule2 =
            rule1
                { left = left'
                , right = right'
                , requires = requires'
                }
    in (rename, rule2)
  where
    RulePattern { left, right, requires } = rule1
    originalFreeVariables = freeVariables rule1

{- | Extract the free variables of a 'RulePattern'.
 -}
freeVariables
    :: Ord variable
    => RulePattern Object variable
    -> Set variable
freeVariables RulePattern { left, right, requires } =
    Set.unions
        [ (Valid.freeVariables . extract) left
        , (Valid.freeVariables . extract) right
        , Predicate.freeVariables requires
        ]

{- | Apply the given function to all variables in a 'RulePattern'.
 -}
mapVariables
    :: Ord variable2
    => (variable1 -> variable2)
    -> RulePattern Object variable1
    -> RulePattern Object variable2
mapVariables mapping rule1 =
    rule1
        { left = TermLike.mapVariables mapping left
        , right = TermLike.mapVariables mapping right
        , requires = Predicate.mapVariables mapping requires
        , ensures = Predicate.mapVariables mapping ensures
        }
  where
    RulePattern { left, right, requires, ensures } = rule1


{- | Traverse the predicate from the top down and apply substitutions.

The 'freeVariables' annotation is used to avoid traversing subterms that
contain none of the targeted variables.

 -}
substitute
    ::  ( FreshVariable variable
        , SortedVariable variable
        )
    => Map variable (TermLike variable)
    -> RulePattern Object variable
    -> RulePattern Object variable
substitute subst rulePattern' =
    rulePattern'
        { left = TermLike.substitute subst left
        , right = TermLike.substitute subst right
        , requires = Predicate.substitute subst requires
        , ensures = Predicate.substitute subst ensures
        }
  where
    RulePattern { left, right, requires, ensures } = rulePattern'
