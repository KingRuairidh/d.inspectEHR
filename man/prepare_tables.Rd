% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/prepare_tables.R
\name{prepare_tables}
\alias{prepare_tables}
\title{Prepare Small Database Tables}
\usage{
prepare_tables(connection, schema_name)
}
\arguments{
\item{connection}{a connection object created with \code{\link{DBI::dbConnect}}}

\item{schema_name}{a character vector for the target schema within the DB}
}
\value{

}
\description{
Collects and processes some of the smaller database tables:
}
\details{
\itemize{
\item person
\item visit_occurrence
\item visit_detail
\item death
}

As these tables grow, it might be prudent to do this preparation in the DB.
}
