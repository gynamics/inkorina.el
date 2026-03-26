# inkorina.el

Inkscape D-bus interface for Emacs.

This project was inspired by [a blog of Gilles Castel](https://castel.dev/post/lecture-notes-2/). I found there was an elder project [inkmacs](https://github.com/jave/inkmacs) which tried to integrate Inkscape with Emacs on D-bus. However, this repository on github hasn't been updated for 15 years, so I decided to remake one, following the same idea. However, Inkscape's D-bus interfaces are limited. If you want more functions, you may have to add more gtk actions to Inkscape's source code (Or develop an Inkscape python plugin for workflow integration).

`inkorina` is a light-weight implementation which provides several Emacs commands to call Inkscape's gtk actions via D-bus. It doesn't include much concrete workflow integration planned in Inkmacs' README, but it is available as a successor of Inkmacs. I am more interested in introduce a handwrite-friendly UI in Emacs currently, Inkscape is an unsuccessful experiment.

## Installation

``` emacs-lisp
;; Install from Github, for Emacs-30+
(use-package inkorina :vc (:url "https://github.com/gynamics/inkorina.el"))
```

## Usage

Currently we implemented these commands:

- `inkorina-launch`: Launch an Inkscape instance if there is no Inkscape running.
- `inkorina-quit`: Close current Inkscape instance.
- `inkorina-action-activate`: Activate one gtk action of Inkscape via D-bus. This is a core function for IPC between Emacs and Inkscape. It provides completions for almost all gtk actions.
- `inkorina-file-open`: Open an SVG file in new window.
- `inkorina-file-close`: Close current file in Inkscape.
- `inkorina-dialog-open`: Open a dialog in Inkscape.
- `inkorina-tool-switch`: Switch tool in Inkscape.
- `inkorina-import-svg`: Import a given SVG file to Inkscape. This is implemented by pasting, so it doesn't work on wayland.
- `inkorina-import-svg-at-point`: Import SVG overlay under point in Emacs to Inkscape. Also won't work on wayland.
- `inkorina-edit-svg-at-point`: Open SVG overlay under point in Emacs to Inkscape.
- `inkorina-export-latex`: An automated workflow which exports current document to PDF with LaTex code to embed the PDF.
