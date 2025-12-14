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
  (interactive "fExport to file: ")
  (when (inkorina--live-p)
    (inkorina--action-activate
     inkorina--inkscape-root-object "export-filename"
     `(:array (:variant ,file)) '(:array :signature "{sv}"))
    (inkorina--action-activate
     inkorina--inkscape-root-object "export-type"
     `(:array (:variant "pdf")) '(:array :signature "{sv}"))
    (inkorina--action-activate
     inkorina--inkscape-root-object "export-latex"
     `(:array (:variant t)) '(:array :signature "{sv}"))
    (inkorina--action-activate
     inkorina--inkscape-root-object "do-export"
     `(:array :signature "v") '(:array :signature "{sv}"))))

(defun inkorina-edit-svg-at-point ()
  "Edit SVG overlay displayed at point."
  (interactive)
  (inkorina-launch)
  (when-let ((ov (car (overlays-at (point)))))
    (let ((disp (overlay-get ov 'display)))
      (when (and (equal (car disp) 'image)
                 (equal (plist-get (cdr disp) :type) 'svg))
        (let ((f (plist-get (cdr disp) :file)))
          (inkorina-file-open f))))))

(provide 'inkorina)

;;; inkorina.el ends here
