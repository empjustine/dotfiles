import XMonad hiding (Tall)
import Solarized

import qualified XMonad.StackSet as StackSet

import XMonad.Hooks.DynamicLog(xmobarPP, xmobarColor, dynamicLogWithPP, ppOutput, ppTitle, ppCurrent, ppUrgent, ppVisible, shorten, wrap)
import XMonad.Hooks.ManageDocks(manageDocks, avoidStruts, ToggleStruts(..))
import XMonad.Util.Run(spawnPipe)
import System.IO(hPutStrLn)

import XMonad.Layout.HintedTile(HintedTile(..), Orientation(Tall, Wide),  Alignment(TopLeft))
import XMonad.Layout.Named(named)
import XMonad.Layout.NoBorders(smartBorders)
import XMonad.Layout.Magnifier(magnifiercz')
import XMonad.Layout.Dishes(Dishes(..))
import XMonad.Layout.FixedColumn(FixedColumn(..))

import XMonad.Layout.Accordion(Accordion(..))

import XMonad.Actions.RotSlaves(rotSlavesUp, rotSlavesDown)
import XMonad.Util.Cursor(setDefaultCursor, xC_left_ptr)
import XMonad.Hooks.EwmhDesktops(fullscreenEventHook)
import XMonad.Hooks.Place(placeHook, simpleSmart)

import XMonad.Actions.DynamicWorkspaces(removeWorkspace, selectWorkspace, withWorkspace, withNthWorkspace, renameWorkspace)
import XMonad.Actions.CopyWindow(copy)
import XMonad.Prompt(defaultXPConfig)

-- allows easier keymapping
import XMonad.Util.EZConfig(additionalKeys)

main = do
  xmobarPipe <- spawnPipe "xmobar $DOTFILES_HOME/xmobar/top.hs"
  xmonad $ defaultConfig
    { terminal = myTerminal
    , modMask = myModMask

    , layoutHook = myLayoutHook
    , handleEventHook = fullscreenEventHook
    , logHook = myLogHook xmobarPipe
    , manageHook = manageDocks <+> myManageHook <+> manageHook defaultConfig

    , workspaces = myWorkspaces

    , startupHook = setDefaultCursor xC_left_ptr
    , normalBorderColor = solarizedBase01
    , focusedBorderColor = solarizedRed
    , borderWidth = 1

    } `additionalKeys`
    [ ((controlMask .|. mod1Mask, xK_t), spawn myTerminal)
    , ((myModMask, xK_b), sendMessage ToggleStruts)
    , ((controlMask, xK_Print), spawn "sleep 0.2; scrot -s")
    , ((0, xK_Print), spawn "scrot")
    ] `additionalKeys` myWorkspaceKeys
      `additionalKeys` myDynamicWorkspacesKeys
      `additionalKeys` myRotationKeys
  where
    myTerminal = "/usr/bin/xterm"

    myModMask = mod4Mask

    numLockKeys =
      [ xK_7, xK_8, xK_9
      , xK_4, xK_5, xK_6
      , xK_1, xK_2, xK_3
      , xK_0, xK_minus, xK_equal
      ]

    numKeys = [xK_1..xK_9] ++ [xK_0, xK_minus, xK_equal]

    greekAlphabet =
      [ "alpha  ", "beta   ", "gamma  "
      , "delta  ", "epsilon", "zeta   "
      , "eta    ", "theta  ", "iota   "
      , "kappa  ", "lambda ", "mu     "
      , "nu     ", "xi     ", "omicron"
      , "pi     ", "rho    ", "sigma  "
      , "tau    ", "phi    ", "chi    "
      , "psi    ", "omega  "
      ]

    myWorkspaces = (map show [1..9]) ++ ["0", "-", "+"]

    myRotationKeys =
      [ ((myModMask, xK_H), rotSlavesDown)
      , ((myModMask, xK_L), rotSlavesUp)
      ]

    myWorkspaceKeys =
      [((m .|. myModMask, k), windows $ f i)
        | (i, k) <- zip myWorkspaces numKeys
        , (f, m) <- [(StackSet.greedyView, 0), (StackSet.shift, shiftMask)]
      ]

    myDynamicWorkspacesKeys =
      [ ((myModMask .|. shiftMask, xK_BackSpace), removeWorkspace)
      , ((myModMask .|. shiftMask, xK_v        ), selectWorkspace defaultXPConfig)
      , ((myModMask              , xK_m        ),   withWorkspace defaultXPConfig (windows . StackSet.shift))
      , ((myModMask .|. shiftMask, xK_m        ),   withWorkspace defaultXPConfig (windows . copy   ))
      , ((myModMask .|. shiftMask, xK_r        ), renameWorkspace defaultXPConfig)
      ] ++
      -- mod-[1..9]       %! Switch to workspace N
        zip (zip (repeat (myModMask)) [xK_1..xK_9]) (map (withNthWorkspace StackSet.greedyView) [0..])
        ++
      -- mod-shift-[1..9] %! Move client to workspace N
        zip (zip (repeat (myModMask .|. shiftMask)) [xK_1..xK_9]) (map (withNthWorkspace StackSet.shift) [0..])


    myLogHook p = dynamicLogWithPP $ myPP
      { ppOutput = hPutStrLn p
      }

    myPP = xmobarPP
      { ppTitle   = xmobarColor solarizedCyan  ""
      , ppCurrent = xmobarColor solarizedRed "" . wrap "" ""
      , ppUrgent  = xmobarColor solarizedMagenta    "" . wrap "" ""
      , ppVisible = xmobarColor solarizedViolet  "" . wrap "" ""
      }

    myManageHook = composeAll
      [ appName =? "push_setup"           --> doFloat -- git-gui push modal dialogs
      , appName =? "__console____o2____d" --> doFloat
      , appName =? "__console____o1____d" --> doFloat
      , appName =? "Download"             --> doFloat -- firefox
      ]

    myLayoutHook = avoidStruts $ smartBorders (code ||| mirror ||| tall ||| dishes ||| full)
      where
        tall        = named "TALL" $ hintedTile Tall
        mirror      = named "WIDE" $ hintedTile Wide
        hintedTile  =                HintedTile nmaster deltaRatio goldenRatio TopLeft

        full        = named "FULL" $ Full
        code        = named "CODE" $ FixedColumn nmaster 20 80 10 -- magnifiercz' magniRatio $ FixedColumn nmaster 20 80 10
        dishes      = named "DISH" $ Dishes nmaster goldenRatio

        nmaster     = 1
        deltaRatio  = (5/100)
        magniRatio  = 1.4
        goldenRatio = (2/(1+(toRational(sqrt(5)::Double))))

