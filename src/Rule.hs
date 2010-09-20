{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -F -pgmF she #-}
module Rule where

import Expr

import Opt hiding (EqRepr)
import Debug.Trace
import Data.Maybe
import Data.List (groupBy,sort, sortBy)
import Control.Monad
import Data.List (zipWith4)
import Data.Either
import Data.Function

type ID = Int

data Pattern = PExpr (TExpr Pattern)
             | PAny ID
             | PLit Lit Pattern
             | PFun (Lit -> Lit -> Lit) Pattern Pattern



type Constraint = [(ID, EqRepr)] -> Opt Bool
data Rule = Rule Pattern Pattern


(~>) = Rule
forall3 f = f (PAny 1) (PAny 2) (PAny 3)
forall2 f = f (PAny 1) (PAny 2)
forall1 f = f (PAny 1)

rAnd x y  = PExpr (And x y)
rOr x y   = PExpr (Or x y)
rAdd x y  = PExpr (Add x y)
rMul x y  = PExpr (Mul x y)
rInt x    = PExpr (Lit $ LInteger x)
rBool x   = PExpr (Lit $ LBool x)
rTrue     = rBool True
rFalse    = rBool False
rVar x    = PExpr (Var x)
rEq x y   = PExpr (Eq x y)
rIf x y z = PExpr (If x y z)
pInt x    = PLit (LInteger (error "don't peek here")) x
pBool x   = PLit (LBool (error "don't peek here")) x

plus = PFun $ \(LInteger i) (LInteger j) ->  (LInteger $ i + j)
mul  = PFun $ \(LInteger i) (LInteger j) ->  (LInteger $ i * j)
eqI  = PFun $ \(LInteger i) (LInteger j) ->  (LBool $ i == j)
eqB  = PFun $ \(LBool x)    (LBool y)    ->  (LBool $ x == y)

rules :: [(Int,Rule)]
rules = map (\r -> (getRuleDepth r, r)) $
        [ assoc rAdd
        , assoc rMul
        , assoc rAnd
        , assoc rOr
        , commute rAdd
        , commute rMul
        , commute rAnd
        , commute rOr
        , commute rEq
        , identity rAdd  (rInt 0)
        , identity rMul  (rInt 1)
        , identity rAnd  (rTrue)
        , identity rOr   (rFalse)
        , zero rMul (rInt 0)
        , zero rAnd (rFalse)
        , zero rOr  (rTrue)

        , eval (rAdd `on` pInt)  plus pInt
        , eval (rMul `on` pInt)  mul pInt
        , eval (rEq  `on` pInt)  eqI pBool
        , eval (rEq  `on` pBool) eqB pBool

        , forall3 $ \x y z -> rMul x (rAdd y z) ~> rAdd (rMul x y) (rMul x z) -- distr ....
        , forall3 $ \x y z -> rAdd (rMul x y) (rMul x z) ~> rMul x (rAdd y z)
        , forall1 $ \x -> x `rEq` x ~> rTrue
        , forall2 $ \x y -> rIf (rTrue) x y ~> x
        , forall2 $ \x y -> rIf (rFalse) x y ~> y
        , forall2 $ \x y -> rIf y x x ~> x
--        , forall4 $ \x y z a -> a `op` (rIf y x z) ~> rIf y (x `op` y) (z `op` y)
        ] 

zero op v     = forall1 $ \x -> (x `op` v) ~> v
identity op v = forall1 $ \x -> (x `op` v) ~> x        
commute op    = forall2 $ \x y -> (x `op` y) ~> (y `op` x)
assoc op      = forall3 $ \x y z -> ((x `op` y) `op` z) ~> (x `op` (y `op` z))
eval op sop res = forall2 $ \x y -> (x `op` y) ~> res (x `sop` y)

getRuleDepth :: Rule -> Int
getRuleDepth (Rule r _) = getDepth r
  where
    getDepth :: Pattern -> Int
    getDepth r = case r of
        PExpr (Lit _) -> 0
        PExpr (Var _) -> 0
        PExpr (And p q) -> binDepth p q
        PExpr (Or p q)  -> binDepth p q
        PExpr (Mul p q) -> binDepth p q
        PExpr (Add p q) -> binDepth p q
        PExpr (Eq p q)  -> binDepth p q
        PExpr (If p q z) -> 1 + maximum [getDepth p, getDepth q, getDepth z]
        PAny _          -> 0
        PLit _ _        -> 0
     where
        binDepth p q = 1 + max (getDepth p) (getDepth q)

-- returns True when nothing matched
apply :: Rule -> EqRepr -> Opt Bool
apply (Rule p1 p2) cls = do
    ma <- applyPattern p1 cls
    -- TODO: check so if id maps to two different things in ma, that they are equal
    -- TODO: check if the code works :)
    --trace ("apply: " ++ show ma) $ return ()
    ma <- filterM (\l -> do 
        let same = map (map  snd) 
                     $ groupBy (\x y -> fst x == fst y) 
                     $ sortBy (\x y -> compare (fst x) (fst y)) $ rights l
        liftM and $ mapM eqRec same
        ) ma
    --liftM null $ mapM (buildPattern' cls p2) ma
    
    list <- mapM (buildPattern (Just cls) p2) $ ma
    --ls <- mapM (union cls) list
    return $ null list

--    mapM_ ls (markDirty

eqRec :: [EqRepr] -> Opt Bool
eqRec [] = return True
eqRec (x:[])   = return True
eqRec (x:y:xs) = liftM2 (&&) (equivalent x y) (eqRec (y:xs))

buildPattern :: Maybe EqRepr -> Pattern -> [Either (ID, Lit) (ID,EqRepr)] -> Opt EqRepr
buildPattern cls p ma = case p of
    PExpr (Lit i) -> addTermToClass (EqExpr $ Lit i) cls
    PExpr (Var x) -> addTermToClass (EqExpr $ Var x) cls
    PExpr (Add q1 q2) -> addBinTermToClass Add q1 q2
    PExpr (Mul q1 q2) -> addBinTermToClass Mul q1 q2
    PExpr (And q1 q2) -> addBinTermToClass And q1 q2
    PExpr (Or q1 q2)  -> addBinTermToClass Or q1 q2
    PExpr (Eq q1 q2)  -> addBinTermToClass Eq q1 q2
    PExpr (If q1 q2 q3) -> do
        p1 <- buildPattern Nothing q1 ma
        p2 <- buildPattern Nothing q2 ma
        p3 <- buildPattern Nothing q3 ma
        c <- addTermToClass (EqExpr $ If p1 p2 p3) cls
        c `dependOn` [p1,p2,p3]
        return c
    PAny i     -> do
        let c = fromJust $ lookup i $ rights ma
        maybe (return c) (union c) cls
    PLit _ v -> do
        r <- literal v
        c <- addTermToClass (EqExpr $ Lit r) cls
        return c
        
  where
    addBinTermToClass op q1 q2 = do
        p1 <- buildPattern Nothing q1 ma
        p2 <- buildPattern Nothing q2 ma
        c <- addTermToClass  (EqExpr $ p1 `op` p2) cls
        c `dependOn` [p1,p2]
        return c
    literal :: Pattern -> Opt Lit
    literal p = case p of
       PFun f p1 p2 -> do
         q1 <- literal p1
         q2 <- literal p2
         return $ f q1 q2
       PLit _ v -> literal v
       PAny i -> do  
         return $ fromJust $ lookup i $ lefts ma
 

combineConst2 :: [[a]] -> [[a]] -> Maybe [a]
combineConst2 [] _  = Nothing
combineConst2 _ []  = Nothing
combineConst2 xs ys = Just . concat $ [x ++ y | x <- xs, y <- ys]

combineConst3 :: [[a]] -> [[a]] -> [[a]] -> Maybe [a]
combineConst3 [] _  _   = Nothing
combineConst3 _  [] _   = Nothing
combineConst3 _  _  []  = Nothing
combineConst3 xs ys zs = Just . concat $ [x ++ y ++ z | x <- xs, y <- ys, z <- zs]

applyPattern :: Pattern -> EqRepr -> Opt [[Either (ID, Lit) (ID,EqRepr)]]
applyPattern pattern cls = do 
    elems <- getElems cls
    case pattern of
        PExpr (Lit i) -> liftM catMaybes $ forM elems $ \rep -> case rep of
            EqExpr (Lit l) | i == l -> return  $ Just []
            _              -> return Nothing
        PExpr (Var x) -> liftM catMaybes $ forM elems $ \rep -> case rep of
            EqExpr (Var y) | x == y -> return  $ Just []
            _              -> return Nothing
        PExpr (Add q1 q2) -> liftM catMaybes $ forM elems $ \rep -> case rep of
            EqExpr (Add p1 p2) -> combine2 p1 p2 q1 q2 
            _ -> return Nothing
        PExpr (Mul q1 q2) -> liftM catMaybes $ forM elems $ \rep -> case rep of
            EqExpr (Mul p1 p2) -> combine2 p1 p2 q1 q2
            _ -> return Nothing
        PExpr (And q1 q2) -> liftM catMaybes $ forM elems $ \rep -> case rep of
            EqExpr (And p1 p2) -> combine2 p1 p2 q1 q2
            _ -> return Nothing
        PExpr (Or q1 q2) -> liftM catMaybes $ forM elems $ \rep -> case rep of
            EqExpr (Or p1 p2) -> combine2 p1 p2 q1 q2
            _ -> return Nothing
        PExpr (Eq q1 q2) -> liftM catMaybes $ forM elems $ \rep -> case rep of
            EqExpr (Eq p1 p2) -> combine2 p1 p2 q1 q2
            _ -> return Nothing
        PExpr (If q1 q2 q3) -> liftM catMaybes $ forM elems $ \rep -> case rep of
            EqExpr (If p1 p2 p3) -> do
                r1 <- applyPattern q1 p1 
                r2 <- applyPattern q2 p2
                r3 <- applyPattern q3 p3
                return $ combineConst3 r1 r2 r3
            _ -> return Nothing
        PAny i -> return [[Right (i,cls)]]
        PLit (LInteger _) (PAny i) -> liftM catMaybes $ forM elems $ \rep -> case rep of
            EqExpr (Lit l@(LInteger _)) -> return  $  Just [Left (i,l)]
            _              -> return Nothing
        PLit (LBool _) (PAny i) -> liftM catMaybes $ forM elems $ \rep -> case rep of
            EqExpr (Lit l@(LBool _)) -> return  $  Just [Left (i,l)]
            _              -> return Nothing
            
 where
    combine2 p1 p2 q1 q2 = do
       r1 <- applyPattern q1 p1 
       r2 <- applyPattern q2 p2
       return $ combineConst2 r1 r2    

applyRules :: [(Int, Rule)] -> EqRepr -> Opt ()
applyRules rules reps = do
    bs <- mapM apply' rules
    when (and bs) $ updated reps Nothing
  where
    apply' (depth, rule) = do
        dirty <- getDepth reps
        case dirty of
            Nothing -> return True
            Just d 
              | d <= depth -> apply rule reps
              | otherwise -> return True

-- applys a set of rules on all classes
ruleEngine :: [(Int,Rule)] -> Opt ()
ruleEngine rules = do
  classes <- getClasses
  mapM_ (applyRules rules) classes

