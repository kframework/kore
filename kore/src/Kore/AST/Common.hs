{-|
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

This module includes all the data structures necessary for representing
the syntactic categories of a Kore definition that do not need unified
constructs.

Unified constructs are those that represent both meta and object versions of
an AST term in a single data type (e.g. 'UnifiedSort' that can be either
'Sort' or 'Sort')

Please refer to Section 9 (The Kore Language) of the
<http://github.com/kframework/kore/blob/master/docs/semantics-of-k.pdf Semantics of K>.
-}

{-# LANGUAGE TemplateHaskell #-}

module Kore.AST.Common where

import           Control.DeepSeq
                 ( NFData (..) )
import           Data.Deriving
                 ( makeLiftCompare, makeLiftEq, makeLiftShowsPrec )
import           Data.Functor.Classes
import           Data.Functor.Const
                 ( Const )
import           Data.Functor.Identity
                 ( Identity (..) )
import           Data.Hashable
import           Data.String
                 ( fromString )
import qualified Data.Text.Prettyprint.Doc as Pretty
import           Data.Void
                 ( Void )
import           GHC.Generics
                 ( Generic )

import Kore.Syntax
import Kore.Unparser
import Template.Tools
       ( newDefinitionGroup )

{-|'Not' corresponds to the @\not@ branches of the @object-pattern@ and
@meta-pattern@ syntactic categories from the Semantics of K,
Section 9.1.4 (Patterns).

The 'level' type parameter is used to distiguish between the meta- and object-
versions of symbol declarations. It should verify 'MetaOrObject level'.

'notSort' is both the sort of the operand and the sort of the result.

This represents the '¬ notChild' Matching Logic construct.
-}
data Not level child = Not
    { notSort  :: !Sort
    , notChild :: child
    }
    deriving (Functor, Foldable, Traversable, Generic)

$newDefinitionGroup

instance Eq1 (Not level) where
    liftEq = $(makeLiftEq ''Not)

instance Ord1 (Not level) where
    liftCompare = $(makeLiftCompare ''Not)

instance Show1 (Not level) where
    liftShowsPrec = $(makeLiftShowsPrec ''Not)

instance Eq child => Eq (Not level child) where
    (==) = eq1

instance Ord child => Ord (Not level child) where
    compare = compare1

instance Show child => Show (Not level child) where
    showsPrec = showsPrec1

instance Hashable child => Hashable (Not level child)

instance NFData child => NFData (Not level child)

instance Unparse child => Unparse (Not level child) where
    unparse Not { notSort, notChild } =
        "\\not"
        <> parameters [notSort]
        <> arguments [notChild]

    unparse2 Not { notChild } =
        Pretty.parens (Pretty.fillSep ["\\not", unparse2 notChild])

{-|'Rewrites' corresponds to the @\rewrites@ branch of the @object-pattern@
syntactic category from the Semantics of K, Section 9.1.4 (Patterns).

Although there is no 'Meta' version of @\rewrites@, there is a 'level' type
parameter which will always be 'Object'. The object-only restriction is
done at the Pattern level.

'rewritesSort' is both the sort of the operands and the sort of the result.

This represents the 'rewritesFirst ⇒ rewritesSecond' Matching Logic construct.
-}

data Rewrites level child = Rewrites
    { rewritesSort   :: !Sort
    , rewritesFirst  :: child
    , rewritesSecond :: child
    }
    deriving (Functor, Foldable, Traversable, Generic)

$newDefinitionGroup

instance Eq1 (Rewrites level) where
    liftEq = $(makeLiftEq ''Rewrites)

instance Ord1 (Rewrites level) where
    liftCompare = $(makeLiftCompare ''Rewrites)

instance Show1 (Rewrites level) where
    liftShowsPrec = $(makeLiftShowsPrec ''Rewrites)

instance Eq child => Eq (Rewrites level child) where
    (==) = eq1

instance Ord child => Ord (Rewrites level child) where
    compare = compare1

instance Show child => Show (Rewrites level child) where
    showsPrec = showsPrec1

instance Hashable child => Hashable (Rewrites level child)

instance NFData child => NFData (Rewrites level child)

instance Unparse child => Unparse (Rewrites level child) where
    unparse Rewrites { rewritesSort, rewritesFirst, rewritesSecond } =
        "\\rewrites"
        <> parameters [rewritesSort]
        <> arguments [rewritesFirst, rewritesSecond]

    unparse2 Rewrites { rewritesFirst, rewritesSecond } =
        Pretty.parens (Pretty.fillSep
            [ "\\rewrites"
            , unparse2 rewritesFirst
            , unparse2 rewritesSecond
            ])

{-|'Pattern' corresponds to the @object-pattern@ and
@meta-pattern@ syntactic categories from the Semantics of K,
Section 9.1.4 (Patterns).
-}
-- NOTE: If you are adding a case to Pattern, you should add cases in:
-- ASTUtils/SmartConstructors.hs
-- as well as a ton of other places, probably.
data Pattern level domain variable child where
    AndPattern
        :: !(And Sort child) -> Pattern level domain variable child
    ApplicationPattern
        :: !(Application SymbolOrAlias child)
        -> Pattern level domain variable child
    BottomPattern
        :: !(Bottom Sort child) -> Pattern level domain variable child
    CeilPattern
        :: !(Ceil Sort child) -> Pattern level domain variable child
    DomainValuePattern
        :: !(domain child)
        -> Pattern level domain variable child
    EqualsPattern
        :: !(Equals Sort child) -> Pattern level domain variable child
    ExistsPattern
        :: !(Exists Sort variable child) -> Pattern level domain variable child
    FloorPattern
        :: !(Floor Sort child) -> Pattern level domain variable child
    ForallPattern
        :: !(Forall Sort variable child) -> Pattern level domain variable child
    IffPattern
        :: !(Iff Sort child) -> Pattern level domain variable child
    ImpliesPattern
        :: !(Implies Sort child) -> Pattern level domain variable child
    InPattern
        :: !(In Sort child) -> Pattern level domain variable child
    NextPattern
        :: !(Next Sort child) -> Pattern level domain variable child
    NotPattern
        :: !(Not level child) -> Pattern level domain variable child
    OrPattern
        :: !(Or Sort child) -> Pattern level domain variable child
    RewritesPattern
        :: !(Rewrites level child) -> Pattern level domain variable child
    StringLiteralPattern
        :: !StringLiteral -> Pattern level domain variable child
    CharLiteralPattern
        :: !CharLiteral -> Pattern level domain variable child
    TopPattern
        :: !(Top Sort child) -> Pattern level domain variable child
    VariablePattern
        :: !variable -> Pattern level domain variable child
    InhabitantPattern
        :: !Sort -> Pattern level domain variable child
    SetVariablePattern
        :: !(SetVariable variable) -> Pattern level domain variable child

$newDefinitionGroup
{- dummy top-level splice to make ''Pattern available for lifting -}

instance
    (Eq variable, Eq1 domain) =>
    Eq1 (Pattern level domain variable)
  where
    liftEq = $(makeLiftEq ''Pattern)

instance
    (Ord variable, Ord1 domain) =>
    Ord1 (Pattern level domain variable)
  where
    liftCompare = $(makeLiftCompare ''Pattern)

instance
    (Show variable, Show1 domain) =>
    Show1 (Pattern level domain variable)
  where
    liftShowsPrec = $(makeLiftShowsPrec ''Pattern)

deriving instance Generic (Pattern level domain variable child)

instance
    ( Hashable child
    , Hashable variable
    , Hashable (domain child)
    ) =>
    Hashable (Pattern level domain variable child)

instance
    ( NFData child
    , NFData variable
    , NFData (domain child)
    ) =>
    NFData (Pattern level domain variable child)

instance
    (Eq child, Eq variable, Eq1 domain) =>
    Eq (Pattern level domain variable child)
  where
    (==) = eq1

instance
    (Ord child, Ord variable, Ord1 domain) =>
    Ord (Pattern level domain variable child)
  where
    compare = compare1

instance
    (Show child, Show variable, Show1 domain) =>
    Show (Pattern level domain variable child)
  where
    showsPrec = showsPrec1

deriving instance Functor domain => Functor (Pattern level domain variable)

deriving instance Foldable domain => Foldable (Pattern level domain variable)

deriving instance
    Traversable domain => Traversable (Pattern level domain variable)

instance
    ( Unparse child
    , Unparse (domain child)
    , Unparse variable
    ) =>
    Unparse (Pattern level domain variable child)
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
    -> Pattern level domain variable1 child
    -> Pattern level domain variable2 child
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
    -> Pattern level domain variable1 child
    -> f (Pattern level domain variable2 child)
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
    -> Pattern level domain1 variable child
    -> Pattern level domain2 variable child
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
    :: Pattern level (Const Void) variable child
    -> Pattern level domain       variable child
castVoidDomainValues = mapDomainValues (\case {})

{-|Enumeration of patterns starting with @\@
-}
data MLPatternType
    = AndPatternType
    | BottomPatternType
    | CeilPatternType
    | DomainValuePatternType
    | EqualsPatternType
    | ExistsPatternType
    | FloorPatternType
    | ForallPatternType
    | IffPatternType
    | ImpliesPatternType
    | InPatternType
    | NextPatternType
    | NotPatternType
    | OrPatternType
    | RewritesPatternType
    | TopPatternType
    deriving (Show, Generic)

instance Hashable MLPatternType

instance Unparse MLPatternType where
    unparse = ("\\" <>) . fromString . patternString
    unparse2 = ("\\" <>) . fromString . patternString

allPatternTypes :: [MLPatternType]
allPatternTypes =
    [ AndPatternType
    , BottomPatternType
    , CeilPatternType
    , DomainValuePatternType
    , EqualsPatternType
    , ExistsPatternType
    , FloorPatternType
    , ForallPatternType
    , IffPatternType
    , ImpliesPatternType
    , InPatternType
    , NextPatternType
    , NotPatternType
    , OrPatternType
    , RewritesPatternType
    , TopPatternType
    ]

patternString :: MLPatternType -> String
patternString pt = case pt of
    AndPatternType         -> "and"
    BottomPatternType      -> "bottom"
    CeilPatternType        -> "ceil"
    DomainValuePatternType -> "dv"
    EqualsPatternType      -> "equals"
    ExistsPatternType      -> "exists"
    FloorPatternType       -> "floor"
    ForallPatternType      -> "forall"
    IffPatternType         -> "iff"
    ImpliesPatternType     -> "implies"
    InPatternType          -> "in"
    NextPatternType        -> "next"
    NotPatternType         -> "not"
    OrPatternType          -> "or"
    RewritesPatternType    -> "rewrites"
    TopPatternType         -> "top"
