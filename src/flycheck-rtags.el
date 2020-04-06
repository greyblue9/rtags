;;; flycheck-rtags.el --- RTags Flycheck integration -*- lexical-binding: t -*-

;; Copyright (C) 2017 Christian Schwarzgruber

;; Author: Christian Schwarzgruber <c.schwarzgruber.cs@gmail.com>
;; URL: https://github.com/Andersbakken/rtags
;; Version: 0.2
;; Package-Requires: ((emacs "24") (flycheck "0.23") (rtags "2.10"))

;; This file is not part of GNU Emacs.

;; This file is part of RTags (https://github.com/Andersbakken/rtags).
;;
;; RTags is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; RTags is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with RTags.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; C, C++ and Objective-c support for Flycheck, using rtags.
;;

;; Usage:
;;
;; (require 'flycheck-rtags)
;;
;;
;; ;; Optional explicitly select the RTags Flycheck checker for c or c++ major mode.
;; ;; Turn off Flycheck highlighting, use the RTags one.
;; ;; Turn off automatic Flycheck syntax checking rtags does this manually.
;; (defun my-flycheck-rtags-setup ()
;;   "Configure flycheck-rtags for better experience."
;;   (flycheck-select-checker 'rtags)
;;   (setq-local flycheck-check-syntax-automatically nil)
;;   (setq-local flycheck-highlighting-mode nil))
;; (add-hook 'c-mode-hook #'my-flycheck-rtags-setup)
;; (add-hook 'c++-mode-hook #'my-flycheck-rtags-setup)
;; (add-hook 'objc-mode-hook #'my-flycheck-rtags-setup)
;;

;;; Code:

(require 'rtags)

(require 'flycheck)
(eval-when-compile (require 'pcase))

(defgroup flycheck-rtags nil
  "RTags Flycheck integration."
  :prefix "flycheck-"
  :group 'flycheck
  :group 'rtags
  :link '(url-link :tag "Website" "https://github.com/Andersbakken/rtags"))

;; Shamelessly stolen from flycheck-irony
(defcustom flycheck-rtags-error-filter 'identity
  "A function to filter the errors returned by this checker.

See ':error-filter' description in `flycheck-define-generic-checker'.
For an example, take a look at `flycheck-dequalify-error-ids'."
  :type 'function
  :group 'flycheck-rtags)

(defcustom flycheck-rtags-show-all-errors nil
  "Whether to show all errors, or just for the current buffer."
  :type 'boolean
  :group 'flycheck-rtags)

(defun flycheck-rtags--build-error (checker)
  "Flycheck RTags build error function.
CHECKER is the syntax checker used to parse BUFFER."
  (rtags-diagnostics)
  (let* ((diagnostics-buffer (get-buffer rtags-diagnostics-buffer-name))
         (rx (concat "^\\(%FILE_NAME%\\):\\([0-9]+\\):\\([0-9]+\\): \\(\\w+\\): \\(.*\\)$"))
         flycheck-errors file-name)

    (if flycheck-rtags-show-all-errors
        (setq rx (replace-regexp-in-string "%FILE_NAME%" "[^:]+" rx t t))
      (setq file-name (file-truename (buffer-file-name (current-buffer)))
            rx (replace-regexp-in-string "%FILE_NAME%" file-name rx t t)))

    (with-current-buffer diagnostics-buffer
      (save-excursion
        (goto-char (point-min))
        (while (search-forward-regexp rx nil t)
          (let ((file-name (match-string-no-properties 1))
                (line (string-to-number (match-string-no-properties 2)))
                (column (1- (string-to-number (match-string-no-properties 3))))
                (severity (match-string-no-properties 4))
                (text (match-string-no-properties 5))
                buffer project)
            (with-temp-buffer
              (rtags-call-rc :path file-name "--current-project")
              (when (> (point-max) (point-min))
                (setq project (buffer-substring-no-properties (point-min) (1- (point-max))))))
            (setq buffer (get-file-buffer (file-truename file-name)))
            (when (member severity '("warning" "error" "fixit"))
              (push (flycheck-error-new :line line
                                        :column column
                                        :level (pcase severity
                                                 (`"fixit" 'info)
                                                 (`"warning" 'warning)
                                                 ((or `"error" `"fatal") 'error))
                                        :message (concat text
                                                         " -> "
                                                         (string-remove-prefix project file-name))
                                        :checker checker
                                        :buffer buffer
                                        :filename file-name)
                    flycheck-errors))))))
    flycheck-errors))

(defun flycheck-rtags--start (checker callback)
  "Flycheck RTags start function.
CHECKER is the syntax checker (RTags).
CALLBACK is the callback function to call."
  (funcall callback 'finished (flycheck-rtags--build-error checker)))

(defun flycheck-rtags--verify (_checker)
  "Verify the Flycheck RTags syntax CHECKER."
  (list
   (flycheck-verification-result-new
    :label "RTags enabled"
    :message (if rtags-enabled "enabled" "disabled")
    :face (if rtags-enabled 'success '(bold warning)))))

(flycheck-define-generic-checker 'rtags
  "RTags flycheck checker."
  :start 'flycheck-rtags--start
  :verify 'flycheck-rtags--verify
  :modes rtags-supported-major-modes
  :error-filter flycheck-rtags-error-filter)

(add-to-list 'flycheck-checkers 'rtags)

(provide 'flycheck-rtags)

;;; flycheck-rtags.el ends here
