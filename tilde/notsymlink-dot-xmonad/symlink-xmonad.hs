import XMonad
import Solarized

import qualified XMonad.StackSet as StackSet
import XMonad.Hooks.ManageHelpers(doRectFloat)

import XMonad.Hooks.DynamicLog(xmobarPP, xmobarColor, dynamicLogWithPP, ppOutput, ppTitle, shorten)
import XMonad.Hooks.ManageDocks(manageDocks, avoidStruts)
import XMonad.Util.Run(spawnPipe)
import System.IO

import XMonad.Util.EZConfig(additionalKeys)

main = do
  xmobarPipe <- spawnPipe "xmobar $DOTFILES_ROOT/xmobar/top.hs"
  xmonad $ defaultConfig
    { terminal = "uxterm"
    , manageHook = manageDocks <+> myManageHook <+> manageHook defaultConfig
    , layoutHook = avoidStruts  $                   layoutHook defaultConfig
    , normalBorderColor = solarizedBase01
    , focusedBorderColor = solarizedRed
    , workspaces = myWorkspaces
    , modMask = mod4Mask
    , logHook = dynamicLogWithPP xmobarPP
        { ppOutput = hPutStrLn xmobarPipe
        , ppTitle = xmobarColor "green" "" -- . shorten 80
        }
    } `additionalKeys`
        [ ((controlMask .|. mod1Mask, xK_t), spawn "uxterm")
        ]
    --  , ((mod4Mask .|. shiftMask .|. controlMask, xK_Print), spawn "xterm")
    --  , ((controlMask .|. altMask, xK_t), spawn "uxterm")
    --  ]
  where
    myWorkspaces =
      [ "1:alpha"
      , "2:beta"
      , "3:gamma"
      , "4:delta"
      , "5:epsilon"
      , "6:zeta"
      , "7:eta"
      , "8:theta"
      , "9:iota"
      , "0:kappa"
      ]

    myManageHook = composeAll
      [ appName =? "push_setup"           --> doFloat -- git-gui push modal dialogs
      , appName =? "__console____o2____d" --> doFloat
      , appName =? "__console____o1____d" --> doFloat
      , appName =? "Download"             --> doFloat -- firefox
      ]
    --  appName =? "x"                    --> doRectFloat (StackSet.RationalRect (1/4) (1/4) (2/4) (2/4))