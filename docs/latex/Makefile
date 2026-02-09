# Makefile for Low-Cost UMI LaTeX documents
# Usage: make all | make report | make timesync | make slides | make clean

LATEX = pdflatex
LATEXFLAGS = -interaction=nonstopmode -halt-on-error

# Directories
REPORT_DIR = technical_report
TSYNC_DIR = time_sync

# Source files
REPORT = $(REPORT_DIR)/Low-Cost-UMI-Report
REPORT_SLIDES = $(REPORT_DIR)/Low-Cost-UMI-Report-slides
TSYNC = $(TSYNC_DIR)/Time-Sync
TSYNC_SLIDES = $(TSYNC_DIR)/Time-Sync-slides

# Targets
ALL_PDF = $(REPORT).pdf $(REPORT_SLIDES).pdf $(TSYNC).pdf $(TSYNC_SLIDES).pdf

.PHONY: all report report-slides timesync timesync-slides slides clean

all: $(ALL_PDF)

report: $(REPORT).pdf

report-slides: $(REPORT_SLIDES).pdf

timesync: $(TSYNC).pdf

timesync-slides: $(TSYNC_SLIDES).pdf

slides: $(REPORT_SLIDES).pdf $(TSYNC_SLIDES).pdf

# 2-pass build for each document (resolves TOC, refs, page numbers)
$(REPORT).pdf: $(REPORT).tex
	cd $(REPORT_DIR) && $(LATEX) $(LATEXFLAGS) $(notdir $(REPORT)).tex
	cd $(REPORT_DIR) && $(LATEX) $(LATEXFLAGS) $(notdir $(REPORT)).tex

$(REPORT_SLIDES).pdf: $(REPORT_SLIDES).tex
	cd $(REPORT_DIR) && $(LATEX) $(LATEXFLAGS) $(notdir $(REPORT_SLIDES)).tex
	cd $(REPORT_DIR) && $(LATEX) $(LATEXFLAGS) $(notdir $(REPORT_SLIDES)).tex

$(TSYNC).pdf: $(TSYNC).tex
	cd $(TSYNC_DIR) && $(LATEX) $(LATEXFLAGS) $(notdir $(TSYNC)).tex
	cd $(TSYNC_DIR) && $(LATEX) $(LATEXFLAGS) $(notdir $(TSYNC)).tex

$(TSYNC_SLIDES).pdf: $(TSYNC_SLIDES).tex
	cd $(TSYNC_DIR) && $(LATEX) $(LATEXFLAGS) $(notdir $(TSYNC_SLIDES)).tex
	cd $(TSYNC_DIR) && $(LATEX) $(LATEXFLAGS) $(notdir $(TSYNC_SLIDES)).tex

clean:
	cd $(REPORT_DIR) && rm -f *.aux *.log *.out *.toc *.nav *.snm *.vrb *.fls *.fdb_latexmk *.synctex.gz *.pdf
	cd $(TSYNC_DIR) && rm -f *.aux *.log *.out *.toc *.nav *.snm *.vrb *.fls *.fdb_latexmk *.synctex.gz *.pdf
