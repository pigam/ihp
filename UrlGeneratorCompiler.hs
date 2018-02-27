module Foundation.UrlGeneratorCompiler where

import           ClassyPrelude           (when, tshow)
import           Data.Maybe              (fromJust, isJust)
import           Data.Monoid             ((<>))
import           Data.String.Conversions (cs)
import           Data.Text               (Text, intercalate, stripPrefix, toTitle)
import qualified Data.Text
import qualified Foundation.NameSupport
import           Foundation.Router
import           Prelude
import qualified Routes
import qualified System.Directory        as Directory
import qualified Data.Set
c = compile

compile :: IO ()
compile = do
    writeCompiledUrlGenerator (doCompile Routes.match)

doCompile :: Router -> Text
doCompile router =
    let
        namePathPairs = map (\(UrlGenerator path) -> let path' = simplify path in (generateName path', path')) (urlGenerators router (UrlGenerator { path = [] }))
    in
        "module UrlGenerator where\n\n"
        <> "import ClassyPrelude\n"
        <> "import Foundation.UrlGeneratorSupport\n"
        <> "\n\n"
        <> (intercalate "\n\n" $ mkUniq $ map generateUrlGeneratorCode namePathPairs)


writeCompiledUrlGenerator :: Text -> IO ()
writeCompiledUrlGenerator content = do
    let path = "src/UrlGenerator.hs"
    alreadyExists <- Directory.doesFileExist path
    putStrLn $ "Updating " <> cs path
    writeFile (cs path) (cs content)


generateUrlGeneratorCode (Just name, path) = typeDefinition <> "\n" <> implementation
    where
        typeDefinition = (lcfirst name) <> "Path :: " <> typeConstraints <> intercalate " -> " (map compilePathToType (zip (variablesOnly path) [0..]) <> ["Text"])
        implementation = (lcfirst name) <> "Path " <> compileArgs <> " = " <> intercalate " <> " (map compilePath (zip path [0..]))
        typeConstraints =
            if length (variablesOnly path) > 0
            then "(" <> (intercalate ", " $ map compilePathToTypeConstraint (zip (variablesOnly path) [0..])) <> ") => "
            else ""
        compilePath :: (UrlGeneratorPath, Int) -> Text
        compilePath (Constant value, i) = cs $ "\"/" <> value <> "\""
        compilePath (Variable x, i)     = cs $ "\"/\" <> toText arg" <> show i
        compileArgs = intercalate " " $ map fromJust $ filter isJust $ map compileArg $ zip path [0..]
            where
                compileArg :: (UrlGeneratorPath, Int) -> Maybe Text
                compileArg (Variable _, i) = Just $ cs $ "arg" <> show i
                compileArg _               = Nothing
        compilePathToType :: (UrlGeneratorPath, Int) -> Text
        compilePathToType (Variable x, i) = "urlArgument" <> tshow i
        compilePathToTypeConstraint :: (UrlGeneratorPath, Int) -> Text
        compilePathToTypeConstraint (Variable x, i) = "UrlArgument urlArgument" <> tshow i

generateUrlGeneratorCode (Nothing, []) = ""
generateUrlGeneratorCode (Nothing, path) = "-- " <> (cs $ show path)

generateName = generateNewEditName

generateNewEditName :: [UrlGeneratorPath] -> Maybe Text
generateNewEditName [] = Nothing
generateNewEditName path =
    case last path of
        Constant value ->
            if value == "new" || value == "edit" then
                Just (value <> (intercalate "" (map Foundation.NameSupport.pluralToSingular $ unwrappedConstants $ init path)))
            else
                Just (intercalate "" (unwrappedConstants $ map uppercaseFirstLetter path))
        Variable name -> Just (intercalate "" (map Foundation.NameSupport.pluralToSingular $ unwrappedConstants $ path))

unwrappedConstants = map (\(Constant value) -> value) . constantsOnly

constantsOnly list = filter isConstant list
    where
        isConstant (Constant _) = True
        isConstant _            = False

variablesOnly list = filter isVariable list
    where
        isVariable (Variable _) = True
        isVariable _            = False

uppercaseFirstLetter (Constant value) = Constant (ucfirst value)
uppercaseFirstLetter otherwise        = otherwise

simplify :: [UrlGeneratorPath] -> [UrlGeneratorPath]
simplify ((Constant "/"):rest) = simplify rest
simplify ((Constant value):rest) =
    case stripPrefix "/" value of
        Just stripped -> (Constant stripped):(simplify rest)
        Nothing       -> (Constant value):(simplify rest)
simplify (x:xs) = x:(simplify xs)
simplify rest = rest

applyFirst f text =
    let (first, rest) = Data.Text.splitAt 1 text
    in (f first) <> rest
lcfirst = applyFirst Data.Text.toLower
ucfirst = applyFirst Data.Text.toUpper

mkUniq :: Ord a => [a] -> [a]
mkUniq = Data.Set.toList . Data.Set.fromList