;;; inkorina.el --- Inkscape accompany Emacs -*- lexical-binding: t -*-

;; Author: gynamics
;; Maintainer: gynamics
;; Package-Version: 0.1
;; Package-Requires: ()
;; Homepage: https://github.com/gynamics/inkorina.el
;; Keywords: applications


;; This file is not part of GNU Emacs

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.


;;; Commentary:

;; D-Bus based Inkscape integration.

;;; Code:

(require 'dbus)


;; should we support multiple inkscape instances?
(defvar inkorina--inkscape-process nil)
(defvar inkorina--inkscape-buffer-name "*Inkorina*")
(defvar inkorina--inkscape-bus "org.inkscape.Inkscape")
(defvar inkorina--inkscape-root-object "/org/inkscape/Inkscape")

(defun inkorina--live-p ()
  "Check if there is a living Inkscape proess to connect."
  (or
   ;; is there already an inkscape process created?
   (process-live-p inkorina--inkscape-process)
   ;; or, is there already an inkscape connection?
   (inkorina--test-connection inkorina--inkscape-bus)))

(defun inkorina--test-connection (bus)
  "Check whether BUS can be found in session bus."
  (and
   ;; bus probe
   (member bus (dbus-list-names :session))
   ;; ping test
   (dbus-ping :session bus 100)))

(defun inkorina-launch ()
  "Ensure there is a working inkscape instance to use."
  (interactive)
  (unless (inkorina--live-p)
    (setq inkorina--inkscape-process
          (make-process
           :name "inkorina"
           :buffer (get-buffer-create inkorina--inkscape-buffer-name)
           :command (list "inkscape" "-g")))
    ;; polling on session bus
    (with-timeout (10 (error "Failed to connect to inkscape instance!"))
      (let ((duration 0.1))
        (while (null (inkorina--test-connection inkorina--inkscape-bus))
          (message "Waiting for inkscape starting...")
          (sleep-for duration))))
    ;; now `dbus-call-method' is safe
    (message "D-Bus connected to inkscape successfully!")))

(defun inkorina--active-windows ()
  "Return a list of object paths of active windows."
  (dbus-introspect-get-node-names :session inkorina--inkscape-bus
                                  (concat inkorina--inkscape-root-object "/window")))

(defun inkorina--active-documents ()
  "Return a list of object paths of active documents."
  (dbus-introspect-get-node-names :session inkorina--inkscape-bus
                                  (concat inkorina--inkscape-root-object "/document")))

(defun inkorina--gtk-action-objects ()
  "Return a list of object paths with gtk actions."
  (mapcan
   (lambda (object-path)
     (when (dbus-introspect-get-interface :session inkorina--inkscape-bus object-path "org.gtk.Actions")
       (list object-path)))
   (dbus-introspect-get-all-nodes :session inkorina--inkscape-bus inkorina--inkscape-root-object)))

(defun inkorina--gtk-actions (object-path)
  "Return an alist of inkscape gtk actions on OBJECT-PATH."
  (when (dbus-introspect-get-interface :session inkorina--inkscape-bus object-path "org.gtk.Actions")
    (dbus-call-method :session inkorina--inkscape-bus object-path "org.gtk.Actions" "DescribeAll")))

(defun inkorina--completing-read-filter (data)
  "Return a function which completes with annotation for DATA."
  (lambda (str pred flag)
    (letrec ((annotation-function
              (lambda (key) (format "\t%S" (cadr (assoc key data))))))
      (pcase flag
        ('nil (try-completion str data pred))
        ('t (all-completions str data pred))
        ('lambda (test-completion str data pred))
        ('metadata
         `(metadata
           . ((annotation-function . ,annotation-function)))))
      )))

(defmacro inkorina--action-activate (object-path action-name &rest args)
  "Activate gtk action ACTION-NAME with ARGS on OBJECT-PATH.
OBJECT-PATH is an relative path to `inkorina--inkscape-root-object'."
  `(dbus-call-method
    :session inkorina--inkscape-bus ,object-path "org.gtk.Actions" "Activate"
    ,action-name ,@args))

(defun inkorina-action-activate (object-path action-name)
  "Activate gtk action ACTION-NAME on OBJECT-PATH, read arguments interactively."
  (interactive
   (progn
     (inkorina-launch) ;; ensure there is one live instance
     (let* ((object (completing-read "Object: " (inkorina--gtk-action-objects)))
            (action (completing-read "Action: " (inkorina--completing-read-filter
                                                 (inkorina--gtk-actions object)))))
       (list object action))))
  (let ((desc
         (dbus-call-method
          :session inkorina--inkscape-bus object-path "org.gtk.Actions" "Describe" action-name)))
    ;; all inkscape actions takes at most one argument, so we can do it in the stupid way
    (if-let* ((arg2
               (pcase (caddr desc)
                 ('nil '(:array :signature "{sv}"))
                 (_ nil)))
              (arg1
               (pcase (cadr desc)
                 ("" '(:array :signature "v"))
                 ("b" `(:array (:variant ,(y-or-n-p "Argument is? "))))
                 ("i" `(:array (:variant ,(read-number "Argument is integer: "))))
                 ("d" `(:array (:variant ,(read-number "Argument is double: "))))
                 ("s" `(:array (:variant ,(read-string "Argument is string: "))))
                 (_ nil))))
        ;; then
        (inkorina--action-activate object-path action-name arg1 arg2)
      ;; else
      (error (format "Unsupported parameter format %S !" desc)))))

(defun inkorina-quit ()
  "Quit current inkscape process."
  (interactive)
  (when (inkorina--live-p)
    (inkorina--action-activate
     inkorina--inkscape-root-object "quit"
     `(:array :signature "v") '(:array :signature "{sv}"))))

(defun inkorina-file-open (file)
  "Open FILE in inkscape."
  (interactive "fOpen file:")
  (inkorina-launch)
  (inkorina--action-activate
   inkorina--inkscape-root-object "file-open-window"
   `(:array (:variant ,file)) '(:array :signature "{sv}")))

(defun inkorina-file-close ()
  "Close current file in inkscape."
  (interactive)
  (inkorina--action-activate
   inkorina--inkscape-root-object "file-close"
   `(:array :signature "v") '(:array :signature "{sv}")))

(defun inkorina-export-latex (file)
  "Export current document to FILE (in pdf format) and export latex."
  (interactive "FExport to file: ")
  (when (inkorina--live-p)
    (mapc
     (lambda (arg)
       (inkorina--action-activate
        inkorina--inkscape-root-object
        (car arg) `(:array ,@(cdr arg)) '(:array :signature "{sv}")))
     (list
      `("export-filename" (:variant ,file))
      '("export-type" (:variant "pdf"))
      '("export-latex" (:variant t))
      '("export-do" :signature "v")))))

(defun inkorina--select-window ()
  "Select a window node in inkscape."
  (if current-prefix-arg
      (completing-read "Window: " (inkorina--active-windows))
    (car (inkorina--active-windows))))

(defvar inkorina--dialog-data
    '("FillStroke" "Objects" "AlignDistribute" "Transform" "ObjectProperties" "Export" "Swatches" "Text" "FontCollections" "Spellcheck" "Find" "SVGFonts" "LivePathEffect" "Trace" "FilterGallery" "FilterEffects" "ExtensionsGallery" "CloneTiler" "Symbols" "DocumentResources" "Selectors" "XMLEditor" "UndoHistory" "IconPreview" "DocumentProperties" "Preferences" "DebugWindow" "Prototype")
  "Dialog data from `inkscape/src/ui/dialog/dialog-data.cpp'.")

(defun inkorina-dialog-open (dialog &optional window)
  "Open DIALOG in WINDOW in inkscape."
  (interactive
   (if (inkorina--live-p)
       (list
        (completing-read "Open dialog: " inkorina--dialog-data)
        (inkorina--select-window))
     (error "Inkscape is not connected!")))
  (when window
    (let ((object (concat inkorina--inkscape-root-object "/window/" window)))
      (inkorina--action-activate
       object "dialog-open" `(:array (:variant ,dialog)) '(:array :signature "{sv}")))))

(defvar inkorina--tool-data
  '("Select" "Node" "Booleans" "Marker" "Rect" "Arc" "Star" "3DBox" "Spiral" "Pencil" "Pen" "Calligraphic" "Text" "Gradient" "Mesh" "Zoom" "Measure" "Dropper" "Tweak" "Spray" "Connector" "PaintBucket" "Eraser" "LPETool" "Pages" "Picker")
  "Tool data from `inkscape/src/ui/tools/tool-data.cpp'.")

(defun inkorina-tool-switch (tool &optional window)
  "Switch to TOOL in WINDOW of inkscape."
  (interactive
   (if (inkorina--live-p)
       (list
        (completing-read "Switch tool: " inkorina--tool-data)
        (inkorina--select-window))
     (error "Inkscape is not connected!")))
  (when window
    (let ((object (concat inkorina--inkscape-root-object "/window/" window)))
      (inkorina--action-activate
       object "tool-switch" `(:array (:variant ,tool)) '(:array :signature "{sv}")))))

(defun inkorina-import-svg (file &optional window)
  "Paste svg FILE at point to WINDOW in inkscape."
  (interactive
   (progn
     (inkorina-launch) ;; ensure there is one live instance
     (read-file-name "Import file: ")
     (list (inkorina--select-window))))
  (when (and (file-exists-p file)
             window)
    (let ((object (concat inkorina--inkscape-root-object "/window/" window)))
      ;; copy SVG content to system clipboard
      (with-temp-buffer
        (insert-file-contents file)
        (clipboard-kill-ring-save (point-min) (point-max)))
      ;; then paste it to inkscape, this doesn't work in wayland, which
      ;; prohibits access of unfocused applications to clipboard.
      (inkorina-action-activate object "paste"))
    (message "No SVG overlay found under point!")))

(defun inkorina--svg-at-point ()
  "Return file path of SVG overlay at current point."
  (when-let* ((ov (car (overlays-at (point))))
              (disp (overlay-get ov 'display)))
    (when (and (equal (car disp) 'image)
               (equal (plist-get (cdr disp) :type) 'svg))
      (plist-get (cdr disp) :file))))

(defun inkorina-import-svg-at-point (&optional window)
  "Paste svg overlay displayed at point to WINDOW in inkscape.
If prefix given, prompt for WINDOW, else use the first window found."
  (interactive
   (progn
     (inkorina-launch) ;; ensure there is one live instance
     (list (inkorina--select-window))))
  (inkorina-import-svg (inkorina--svg-at-point) window))

(defun inkorina-edit-svg-at-point ()
  "Edit SVG overlay displayed at point in inkscape."
  (interactive)
  (inkorina-launch)
  (when-let ((f (inkorina--svg-at-point)))
    (inkorina-file-open f)))

(provide 'inkorina)

;;; inkorina.el ends here
