{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}

{-# LANGUAGE TemplateHaskell #-}

module Kore.Syntax.PatternF
    ( PatternF (..)
    , mapVariables
    , traverseVariables
    , mapDomainValues
    , castVoidDomainValues
    -- * Pure pattern heads
    , groundHead
    , constant
    ) where

import           Control.DeepSeq
                 ( NFData (..) )
import qualified Data.Deriving as Deriving
import           Data.Functor.Classes
import           Data.Functor.Const
                 ( Const )
import           Data.Functor.Identity
                 ( Identity (..) )
import           Data.Hashable
import           Data.Text
                 ( Text )
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

{- | 'PatternF' is the 'Base' functor of Kore patterns

-}
data PatternF domain variable child
    = AndF           !(And Sort child)
    | ApplicationF   !(Application SymbolOrAlias child)
    | BottomF        !(Bottom Sort child)
    | CeilF          !(Ceil Sort child)
    | DomainValueF   !(domain child)
    | EqualsF        !(Equals Sort child)
    | ExistsF        !(Exists Sort variable child)
    | FloorF         !(Floor Sort child)
    | ForallF        !(Forall Sort variable child)
    | IffF           !(Iff Sort child)
    | ImpliesF       !(Implies Sort child)
    | InF            !(In Sort child)
    | NextF          !(Next Sort child)
    | NotF           !(Not Sort child)
    | OrF            !(Or Sort child)
    | RewritesF      !(Rewrites Sort child)
    | StringLiteralF !StringLiteral
    | CharLiteralF   !CharLiteral
    | TopF           !(Top Sort child)
    | VariableF      !variable
    | InhabitantF    !Sort
    | SetVariableF   !(SetVariable variable)
    deriving (Foldable, Functor, Generic, Traversable)

Deriving.deriveEq1 ''PatternF
Deriving.deriveOrd1 ''PatternF
Deriving.deriveShow1 ''PatternF

instance
    (Eq1 domain, Eq variable, Eq child) =>
    Eq (PatternF domain variable child)
  where
    (==) = eq1
    {-# INLINE (==) #-}

instance
    (Ord1 domain, Ord variable, Ord child) =>
    Ord (PatternF domain variable child)
  where
    compare = compare1
    {-# INLINE compare #-}

instance
    (Show1 domain, Show variable, Show child) =>
    Show (PatternF domain variable child)
  where
    showsPrec = showsPrec1
    {-# INLINE showsPrec #-}

instance
    ( Hashable child
    , Hashable variable
    , Hashable (domain child)
    ) =>
    Hashable (PatternF domain variable child)

instance
    ( NFData child
    , NFData variable
    , NFData (domain child)
    ) =>
    NFData (PatternF domain variable child)

instance
    ( Unparse child
    , Unparse (domain child)
    , Unparse variable
    ) =>
    Unparse (PatternF domain variable child)
  where
    unparse =
        \case
            AndF p           -> unparse p
            ApplicationF p   -> unparse p
            BottomF p        -> unparse p
            CeilF p          -> unparse p
            DomainValueF p   -> unparse p
            EqualsF p        -> unparse p
            ExistsF p        -> unparse p
            FloorF p         -> unparse p
            ForallF p        -> unparse p
            IffF p           -> unparse p
            ImpliesF p       -> unparse p
            InF p            -> unparse p
            NextF p          -> unparse p
            NotF p           -> unparse p
            OrF p            -> unparse p
            RewritesF p      -> unparse p
            StringLiteralF p -> unparse p
            CharLiteralF p   -> unparse p
            TopF p           -> unparse p
            VariableF p      -> unparse p
            InhabitantF s          -> unparse s
            SetVariableF p   -> unparse p

    unparse2 =
        \case
            AndF p           -> unparse2 p
            ApplicationF p   -> unparse2 p
            BottomF p        -> unparse2 p
            CeilF p          -> unparse2 p
            DomainValueF p   -> unparse2 p
            EqualsF p        -> unparse2 p
            ExistsF p        -> unparse2 p
            FloorF p         -> unparse2 p
            ForallF p        -> unparse2 p
            IffF p           -> unparse2 p
            ImpliesF p       -> unparse2 p
            InF p            -> unparse2 p
            NextF p          -> unparse2 p
            NotF p           -> unparse2 p
            OrF p            -> unparse2 p
            RewritesF p      -> unparse2 p
            StringLiteralF p -> unparse2 p
            CharLiteralF p   -> unparse2 p
            TopF p           -> unparse2 p
            VariableF p      -> unparse2 p
            InhabitantF s          -> unparse s
            SetVariableF p   -> unparse p

{- | Use the provided mapping to replace all variables in a 'PatternF' head.

__Warning__: @mapVariables@ will capture variables if the provided mapping is
not injective!

-}
mapVariables
    :: (variable1 -> variable2)
    -> PatternF domain variable1 child
    -> PatternF domain variable2 child
mapVariables mapping =
    runIdentity . traverseVariables (Identity . mapping)
{-# INLINE mapVariables #-}

{- | Use the provided traversal to replace all variables in a 'PatternF' head.

__Warning__: @traverseVariables@ will capture variables if the provided
traversal is not injective!

-}
traverseVariables
    :: Applicative f
    => (variable1 -> f variable2)
    -> PatternF domain variable1 child
    -> f (PatternF domain variable2 child)
traverseVariables traversing =
    \case
        -- Non-trivial cases
        ExistsF any0 -> ExistsF <$> traverseVariablesExists any0
        ForallF all0 -> ForallF <$> traverseVariablesForall all0
        VariableF variable -> VariableF <$> traversing variable
        InhabitantF s -> pure (InhabitantF s)
        SetVariableF (SetVariable variable)
            -> SetVariableF . SetVariable <$> traversing variable
        -- Trivial cases
        AndF andP -> pure (AndF andP)
        ApplicationF appP -> pure (ApplicationF appP)
        BottomF botP -> pure (BottomF botP)
        CeilF ceilP -> pure (CeilF ceilP)
        DomainValueF dvP -> pure (DomainValueF dvP)
        EqualsF eqP -> pure (EqualsF eqP)
        FloorF flrP -> pure (FloorF flrP)
        IffF iffP -> pure (IffF iffP)
        ImpliesF impP -> pure (ImpliesF impP)
        InF inP -> pure (InF inP)
        NextF nxtP -> pure (NextF nxtP)
        NotF notP -> pure (NotF notP)
        OrF orP -> pure (OrF orP)
        RewritesF rewP -> pure (RewritesF rewP)
        StringLiteralF strP -> pure (StringLiteralF strP)
        CharLiteralF charP -> pure (CharLiteralF charP)
        TopF topP -> pure (TopF topP)
  where
    traverseVariablesExists Exists { existsSort, existsVariable, existsChild } =
        Exists existsSort <$> traversing existsVariable <*> pure existsChild
    traverseVariablesForall Forall { forallSort, forallVariable, forallChild } =
        Forall forallSort <$> traversing forallVariable <*> pure forallChild

-- | Use the provided mapping to replace all domain values in a 'PatternF' head.
mapDomainValues
    :: (forall child'. domain1 child' -> domain2 child')
    -> PatternF domain1 variable child
    -> PatternF domain2 variable child
mapDomainValues mapping =
    \case
        -- Non-trivial case
        DomainValueF domainP -> DomainValueF (mapping domainP)
        InhabitantF s -> InhabitantF s
        -- Trivial cases
        AndF andP -> AndF andP
        ApplicationF appP -> ApplicationF appP
        BottomF botP -> BottomF botP
        CeilF ceilP -> CeilF ceilP
        EqualsF eqP -> EqualsF eqP
        ExistsF existsP -> ExistsF existsP
        FloorF flrP -> FloorF flrP
        ForallF forallP -> ForallF forallP
        IffF iffP -> IffF iffP
        ImpliesF impP -> ImpliesF impP
        InF inP -> InF inP
        NextF nextP -> NextF nextP
        NotF notP -> NotF notP
        OrF orP -> OrF orP
        RewritesF rewP -> RewritesF rewP
        StringLiteralF strP -> StringLiteralF strP
        CharLiteralF charP -> CharLiteralF charP
        TopF topP -> TopF topP
        VariableF varP -> VariableF varP
        SetVariableF varP -> SetVariableF varP

{- | Cast a 'PatternF' head with @'Const' 'Void'@ domain values into any domain.

The @Const Void@ domain excludes domain values; the pattern head can be cast
trivially because it must contain no domain values.

 -}
castVoidDomainValues
    :: PatternF (Const Void) variable child
    -> PatternF domain       variable child
castVoidDomainValues = mapDomainValues (\case {})

-- | Given an 'Id', 'groundHead' produces the head of an 'Application'
-- corresponding to that argument.
groundHead :: Text -> AstLocation -> SymbolOrAlias
groundHead ctor location = SymbolOrAlias
    { symbolOrAliasConstructor = Id
        { getId = ctor
        , idLocation = location
        }
    , symbolOrAliasParams = []
    }

-- | Given a head and a list of children, produces an 'ApplicationF'
--  applying the given head to the children
apply :: SymbolOrAlias -> [child] -> PatternF domain variable child
apply patternHead patterns = ApplicationF Application
    { applicationSymbolOrAlias = patternHead
    , applicationChildren = patterns
    }

-- |Applies the given head to the empty list of children to obtain a
-- constant 'ApplicationF'
constant :: SymbolOrAlias -> PatternF domain variable child
constant patternHead = apply patternHead []
