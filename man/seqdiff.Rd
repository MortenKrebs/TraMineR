\name{seqdiff}
\alias{seqdiff}
\alias{print.seqdiff}
\alias{plot.seqdiff}
%- Also NEED an '\alias' for EACH other topic documented here.
\title{Decompose the difference between groups of sequences}
\description{
  Decompose the difference between groups of sequences
}
\usage{
seqdiff(seqdata, group, cmprange = c(0, 1), 
	seqdist_arg=list(method="LCS",norm=TRUE))
}
%- maybe also 'usage' for other objects documented here.
\arguments{
  \item{seqdata}{The sequence to analyse}
  \item{group}{The group variable}
  \item{cmprange}{The range used to compare subsequences}
  \item{seqdist_arg}{argument passed directly to seqdist as a list}
}
\details{
  Analyse for each timestamp the discrepancy of a subsequence (defined by \code{cmprange}) explained by the \code{group} variable.
  The method compute a distance matrix, using \code{\link{seqdist}} for each timestamp and then apply dissassoc to compute the discrepancy explained.
  
  There are print and plot method for the result returned.
}
\value{
  A \code{seqdiff} object, with the following item:
  \item{stat}{A \code{data.frame} with tree statistics, PseudoF, PseudoR2 and PseudoT for each timestamp of the sequence, see \code{\link{dissassoc}}}
  \item{variance}{A \code{data.frame} with the discrepancy of each \code{group} defined by the \code{group} variable and for the whole population at each timestamp}
}
\seealso{\code{\link{dissassoc}} to analyse the association with the whole sequence}
\examples{
## Defining a state sequence object
data(mvad)
mvad.seq <- seqdef(mvad[, 17:86])

## Building dissimilarities
mvad.diff <- seqdiff(mvad.seq, group=mvad$gcse5eq)
print(mvad.diff)
plot(mvad.diff)
plot(mvad.diff, stat="Variance")
}