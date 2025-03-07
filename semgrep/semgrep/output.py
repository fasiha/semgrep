import contextlib
import json
import logging
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any
from typing import cast
from typing import Dict
from typing import FrozenSet
from typing import Generator
from typing import IO
from typing import Iterator
from typing import List
from typing import NamedTuple
from typing import Optional
from typing import Set
from typing import Tuple

import colorama

from semgrep import __VERSION__
from semgrep import config_resolver
from semgrep.constants import BREAK_LINE
from semgrep.constants import BREAK_LINE_CHAR
from semgrep.constants import BREAK_LINE_WIDTH
from semgrep.constants import CLI_RULE_ID
from semgrep.constants import MAX_LINES_FLAG_NAME
from semgrep.constants import OutputFormat
from semgrep.error import FINDINGS_EXIT_CODE
from semgrep.error import Level
from semgrep.error import MatchTimeoutError
from semgrep.error import SemgrepError
from semgrep.external.junit_xml import TestSuite  # type: ignore[attr-defined]
from semgrep.external.junit_xml import to_xml_report_string  # type: ignore[attr-defined]
from semgrep.profile_manager import ProfileManager
from semgrep.rule import Rule
from semgrep.rule_match import RuleMatch
from semgrep.stats import make_loc_stats
from semgrep.stats import make_target_stats
from semgrep.util import is_url
from semgrep.util import with_color

logger = logging.getLogger(__name__)


def color_line(
    line: str,
    line_number: int,
    start_line: int,
    start_col: int,
    end_line: int,
    end_col: int,
) -> str:
    start_color = 0 if line_number > start_line else start_col
    # column offset
    start_color = max(start_color - 1, 0)
    end_color = end_col if line_number >= end_line else len(line) + 1 + 1
    end_color = max(end_color - 1, 0)
    line = (
        line[:start_color]
        + colorama.Style.BRIGHT
        + line[start_color : end_color + 1]  # want the color to include the end_col
        + colorama.Style.RESET_ALL
        + line[end_color + 1 :]
    )
    return line


def finding_to_line(
    rule_match: RuleMatch,
    color_output: bool,
    per_finding_max_lines_limit: Optional[int],
    show_separator: bool,
) -> Iterator[str]:
    path = rule_match.path
    start_line = rule_match.start.get("line")
    end_line = rule_match.end.get("line")
    start_col = rule_match.start.get("col")
    end_col = rule_match.end.get("col")
    trimmed = 0
    if path:
        lines = rule_match.extra.get("fixed_lines") or rule_match.lines
        if per_finding_max_lines_limit:
            trimmed = len(lines) - per_finding_max_lines_limit
            lines = lines[:per_finding_max_lines_limit]

        for i, line in enumerate(lines):
            line = line.rstrip()
            line_number = ""
            if start_line:
                if color_output:
                    line = color_line(
                        line, start_line + i, start_line, start_col, end_line, end_col  # type: ignore
                    )
                    line_number = f"{colorama.Fore.GREEN}{start_line + i}{colorama.Style.RESET_ALL}"
                else:
                    line_number = f"{start_line + i}"

            yield f"{line_number}:{line}" if line_number else f"{line}"
        trimmed_str = (
            f" [hid {trimmed} additional lines, adjust with {MAX_LINES_FLAG_NAME}] "
        )
        if per_finding_max_lines_limit != 1:
            if trimmed > 0:
                yield trimmed_str.center(BREAK_LINE_WIDTH, BREAK_LINE_CHAR)
            elif show_separator:
                yield BREAK_LINE


def build_normal_output(
    rule_matches: List[RuleMatch],
    color_output: bool,
    per_finding_max_lines_limit: Optional[int],
) -> Iterator[str]:
    RESET_COLOR = colorama.Style.RESET_ALL if color_output else ""
    GREEN_COLOR = colorama.Fore.GREEN if color_output else ""
    YELLOW_COLOR = colorama.Fore.YELLOW if color_output else ""
    RED_COLOR = colorama.Fore.RED if color_output else ""
    BLUE_COLOR = colorama.Fore.BLUE if color_output else ""

    last_file = None
    last_message = None
    sorted_rule_matches = sorted(rule_matches, key=lambda r: (r.path, r.id))
    for rule_index, rule_match in enumerate(sorted_rule_matches):

        current_file = rule_match.path
        check_id = rule_match.id
        message = rule_match.message
        severity = rule_match.severity.lower()
        fix = rule_match.fix
        if last_file is None or last_file != current_file:
            if last_file is not None:
                yield ""
            yield f"{GREEN_COLOR}{current_file}{RESET_COLOR}"
            last_message = None
        # don't display the rule line if the check is empty
        if (
            check_id
            and check_id != CLI_RULE_ID
            and (last_message is None or last_message != message)
        ):
            severity_prepend = ""
            if severity:
                if severity == "error":
                    severity_prepend = f"{RED_COLOR}severity:{severity} "
                elif severity == "warning":
                    severity_prepend = f"{YELLOW_COLOR}severity:{severity} "
                else:
                    severity_prepend = f"severity:{severity} "
            yield f"{severity_prepend}{YELLOW_COLOR}rule:{check_id}: {message}{RESET_COLOR}"

        last_file = current_file
        last_message = message
        next_rule_match = (
            sorted_rule_matches[rule_index + 1]
            if rule_index != len(sorted_rule_matches) - 1
            else None
        )
        is_same_file = (
            next_rule_match.path == rule_match.path if next_rule_match else False
        )
        yield from finding_to_line(
            rule_match,
            color_output,
            per_finding_max_lines_limit,
            is_same_file,
        )

        if fix:
            yield f"{BLUE_COLOR}autofix:{RESET_COLOR} {fix}"
        elif rule_match.fix_regex:
            fix_regex = rule_match.fix_regex
            yield f"{BLUE_COLOR}autofix:{RESET_COLOR} s/{fix_regex.get('regex')}/{fix_regex.get('replacement')}/{fix_regex.get('count', 'g')}"


def _build_time_target_json(
    rules: List[Rule],
    target: Path,
    match_time_matrix: Dict[Tuple[str, str], float],
) -> Dict[str, Any]:
    target_json: Dict[str, Any] = {}
    path_str = str(target)
    target_json["path"] = path_str
    target_json["match_times"] = [
        match_time_matrix.get((rule.id, path_str), 0.0) for rule in rules
    ]
    return target_json


def _build_time_json(
    rules: List[Rule],
    targets: Set[Path],
    match_time_matrix: Dict[Tuple[str, str], float],  # (rule, target) -> duration
) -> Dict[str, Any]:
    """Convert match times to a json-ready format.

    Match times are obtained for each pair (rule, target) by running
    semgrep-core. They exclude parsing time. One of the applications is
    to estimate the performance of a rule, assuming the cost of parsing
    the target file will become negligible once we run many rules on the
    same AST.
    """
    time = {}
    # this list of all rules names is given here so they don't have to be
    # repeated for each target in the 'targets' field, saving space.
    time["rules"] = [{"id": rule.id} for rule in rules]
    time["targets"] = [
        _build_time_target_json(rules, target, match_time_matrix) for target in targets
    ]
    return time


def build_output_json(
    rule_matches: List[RuleMatch],
    semgrep_structured_errors: List[SemgrepError],
    all_targets: Set[Path],
    show_json_stats: bool,
    report_time: bool,
    filtered_rules: List[Rule],
    match_time_matrix: Dict[Tuple[str, str], float],
    profiler: Optional[ProfileManager] = None,
    debug_steps_by_rule: Optional[Dict[Rule, List[Dict[str, Any]]]] = None,
) -> str:
    output_json: Dict[str, Any] = {}
    output_json["results"] = [rm.to_json() for rm in rule_matches]
    if debug_steps_by_rule:
        output_json["debug"] = [
            {r.id: steps for r, steps in debug_steps_by_rule.items()}
        ]
    output_json["errors"] = [e.to_dict() for e in semgrep_structured_errors]
    if show_json_stats:
        output_json["stats"] = {
            "targets": make_target_stats(all_targets),
            "loc": make_loc_stats(all_targets),
            "profiler": profiler.dump_stats() if profiler else None,
        }
    if report_time:
        output_json["time"] = _build_time_json(
            filtered_rules, all_targets, match_time_matrix
        )
    return json.dumps(output_json)


def build_junit_xml_output(
    rule_matches: List[RuleMatch], rules: FrozenSet[Rule]
) -> str:
    """
    Format matches in JUnit XML format.
    """
    test_cases = [match.to_junit_xml() for match in rule_matches]
    ts = TestSuite("semgrep results", test_cases)
    return cast(str, to_xml_report_string([ts]))


def _sarif_tool_info() -> Dict[str, Any]:
    return {"name": "semgrep", "semanticVersion": __VERSION__}


def _sarif_notification_from_error(error: SemgrepError) -> Dict[str, Any]:
    error_dict = error.to_dict()
    descriptor = error_dict["type"]

    error_to_sarif_level = {
        Level.ERROR.name.lower(): "error",
        Level.WARN.name.lower(): "warning",
    }
    level = error_to_sarif_level[error_dict["level"]]

    message = error_dict.get("message")
    if message is None:
        message = error_dict.get("long_msg")
    if message is None:
        message = error_dict.get("short_msg", "")

    return {
        "descriptor": {"id": descriptor},
        "message": {"text": message},
        "level": level,
    }


def build_sarif_output(
    rule_matches: List[RuleMatch],
    rules: FrozenSet[Rule],
    semgrep_structured_errors: List[SemgrepError],
) -> str:
    """
    Format matches in SARIF v2.1.0 formatted JSON.

    - written based on https://help.github.com/en/github/finding-security-vulnerabilities-and-errors-in-your-code/about-sarif-support-for-code-scanning
    - which links to this schema https://github.com/oasis-tcs/sarif-spec/blob/master/Schemata/sarif-schema-2.1.0.json
    - full spec is at https://docs.oasis-open.org/sarif/sarif/v2.1.0/cs01/sarif-v2.1.0-cs01.html
    """

    output_dict = {
        "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        **_sarif_tool_info(),
                        "rules": [rule.to_sarif() for rule in rules],
                    }
                },
                "results": [match.to_sarif() for match in rule_matches],
                "invocations": [
                    {
                        "toolExecutionNotifications": [
                            _sarif_notification_from_error(e)
                            for e in semgrep_structured_errors
                        ],
                    }
                ],
            },
        ],
    }
    return json.dumps(output_dict)


def iter_emacs_output(
    rule_matches: List[RuleMatch], rules: FrozenSet[Rule]
) -> Iterator[str]:
    last_file = None
    last_message = None
    sorted_rule_matches = sorted(rule_matches, key=lambda r: (r.path, r.id))
    for _, rule_match in enumerate(sorted_rule_matches):
        current_file = rule_match.path
        check_id = rule_match.id
        message = rule_match.message
        severity = rule_match.severity.lower()
        start_line = rule_match.start.get("line")
        start_col = rule_match.start.get("col")
        line = rule_match.lines[0].rstrip()
        info = ""
        if check_id and check_id != CLI_RULE_ID:
            check_id = check_id.split(".")[-1]
            info = f"({check_id})"
        yield f"{current_file}:{start_line}:{start_col}:{severity}{info}:{line}"


def build_emacs_output(rule_matches: List[RuleMatch], rules: FrozenSet[Rule]) -> str:
    return "\n".join(list(iter_emacs_output(rule_matches, rules)))


def build_vim_output(rule_matches: List[RuleMatch], rules: FrozenSet[Rule]) -> str:
    severity = {
        "INFO": "I",
        "WARNING": "W",
        "ERROR": "E",
    }

    def _get_parts(rule_match: RuleMatch) -> List[str]:
        return [
            str(rule_match.path),
            str(rule_match.start["line"]),
            str(rule_match.start["col"]),
            severity[rule_match.severity],
            rule_match.id,
            rule_match.message,
        ]

    return "\n".join(":".join(_get_parts(rm)) for rm in rule_matches)


class OutputSettings(NamedTuple):
    output_format: OutputFormat
    output_destination: Optional[str]
    error_on_findings: bool
    verbose_errors: bool
    strict: bool
    output_per_finding_max_lines_limit: Optional[int]
    json_stats: bool
    json_time: bool
    timeout_threshold: int = 0


@contextlib.contextmanager
def managed_output(output_settings: OutputSettings) -> Generator:  # type: ignore
    """
    Context manager to capture uncaught exceptions &
    """
    output_handler = OutputHandler(output_settings)
    try:
        yield output_handler
    except Exception as ex:
        output_handler.handle_unhandled_exception(ex)
    finally:
        output_handler.close()


class OutputHandler:
    """
    Handle all output in a central location. Rather than calling `print_stderr` directly,
    you should call `handle_*` as appropriate.

    In normal usage, it should be constructed via the contextmanager, `managed_output`. It ensures that everything
    is handled properly if exceptions are thrown.

    If you need to stop execution immediately (think carefully if you really want this!), throw an exception.
    If this is normal behavior, the exception _must_ inherit from `SemgrepError`.

    If you want execution to continue, _report_ the exception via the appropriate `handle_*` method.
    """

    def __init__(
        self,
        output_settings: OutputSettings,
        stderr: IO = sys.stderr,
        stdout: IO = sys.stdout,
    ):
        self.settings = output_settings
        self.stderr = stderr
        self.stdout = stdout

        self.rule_matches: List[RuleMatch] = []
        self.debug_steps_by_rule: Dict[Rule, List[Dict[str, Any]]] = {}
        self.stats_line: Optional[str] = None
        self.all_targets: Set[Path] = set()
        self.profiler: Optional[ProfileManager] = None
        self.rules: FrozenSet[Rule] = frozenset()
        self.semgrep_structured_errors: List[SemgrepError] = []
        self.error_set: Set[SemgrepError] = set()
        self.has_output = False
        self.filtered_rules: List[Rule] = []
        self.match_time_matrix: Dict[
            Tuple[str, str], float
        ] = {}  # (rule, target) -> duration

        self.final_error: Optional[Exception] = None

    def handle_semgrep_errors(self, errors: List[SemgrepError]) -> None:
        timeout_errors = defaultdict(list)
        for err in errors:
            if isinstance(err, MatchTimeoutError) and err not in self.error_set:
                self.semgrep_structured_errors.append(err)
                self.error_set.add(err)
                timeout_errors[err.path].append(err.rule_id)
            else:
                self.handle_semgrep_error(err)

        if timeout_errors and self.settings.output_format == OutputFormat.TEXT:
            self.handle_semgrep_timeout_errors(timeout_errors)

    def handle_semgrep_timeout_errors(self, errors: Dict[Path, List[str]]) -> None:
        self.has_output = True
        separator = ", "
        print_threshold_hint = False
        for path in errors.keys():
            num_errs = len(errors[path])
            errors[path].sort()
            error_msg = f"Warning: {num_errs} timeout error(s) in {path} when running the following rules: [{separator.join(errors[path])}]"
            if num_errs == self.settings.timeout_threshold:
                error_msg += f"\nSemgrep stopped running rules on {path} after {num_errs} timeout error(s). See `--timeout-threshold` for more info."
            print_threshold_hint = print_threshold_hint or (
                num_errs > 5 and not self.settings.timeout_threshold
            )
            logger.error(with_color(colorama.Fore.RED, error_msg))

        if print_threshold_hint:
            logger.error(
                with_color(
                    colorama.Fore.RED,
                    f"You can use the `--timeout-threshold` flag to set a number of timeouts after which a file will be skipped.",
                )
            )

    def handle_semgrep_error(self, error: SemgrepError) -> None:
        """
        Reports generic exceptions that extend SemgrepError
        """
        self.has_output = True
        if error not in self.error_set:
            self.semgrep_structured_errors.append(error)
            self.error_set.add(error)
            if self.settings.output_format == OutputFormat.TEXT and (
                error.level != Level.WARN or self.settings.verbose_errors
            ):
                logger.error(str(error))

    def handle_semgrep_core_output(
        self,
        rule_matches_by_rule: Dict[Rule, List[RuleMatch]],
        debug_steps_by_rule: Dict[Rule, List[Dict[str, Any]]],
        stats_line: str,
        all_targets: Set[Path],
        profiler: ProfileManager,
        filtered_rules: List[Rule],
        match_time_matrix: Dict[Tuple[str, str], float],  # (rule, target) -> duration
    ) -> None:
        self.has_output = True
        self.rules = self.rules.union(rule_matches_by_rule.keys())
        self.rule_matches += [
            match
            for matches_of_one_rule in rule_matches_by_rule.values()
            for match in matches_of_one_rule
        ]
        self.profiler = profiler
        self.all_targets = all_targets
        self.stats_line = stats_line
        self.debug_steps_by_rule.update(debug_steps_by_rule)
        self.filtered_rules = filtered_rules
        self.match_time_matrix = match_time_matrix

    def handle_unhandled_exception(self, ex: Exception) -> None:
        """
        This is called by the context manager upon an unhandled exception. If you want to record a final
        error & set the exit code, but keep executing to perform cleanup tasks, call this method.
        """

        if isinstance(ex, SemgrepError):
            self.handle_semgrep_error(ex)
        self.final_error = ex

    def final_raise(self, ex: Optional[Exception], error_stats: Optional[str]) -> None:
        if ex is None:
            return
        if isinstance(ex, SemgrepError):
            if ex.level == Level.ERROR:
                raise ex
            else:
                if self.settings.strict:
                    raise ex
                logger.info(
                    f"{error_stats}; run with --verbose for details or run with --strict to exit non-zero if any file cannot be analyzed"
                )
        else:
            raise ex

    def close(self) -> None:
        """
        Close the output handler.

        This will write any output that hasn't been written so far. It returns
        the exit code of the program.
        """
        if self.has_output:
            output = self.build_output(
                self.settings.output_destination is None and self.stdout.isatty(),
                self.settings.output_per_finding_max_lines_limit,
            )
            if output:
                try:
                    print(output, file=self.stdout)
                except UnicodeEncodeError as ex:
                    raise Exception(
                        "Received output encoding error, please set PYTHONIOENCODING=utf-8"
                    ) from ex
            if self.stats_line:
                logger.info(self.stats_line)

            if self.settings.output_destination:
                self.save_output(self.settings.output_destination, output)

        final_error = None
        error_stats = None
        if self.final_error:
            final_error = self.final_error
        elif self.rule_matches and self.settings.error_on_findings:
            # This exception won't be visible to the user, we're just
            # using this to return a specific error code
            final_error = SemgrepError("", code=FINDINGS_EXIT_CODE)
        elif self.semgrep_structured_errors:
            # make a simplifying assumption that # errors = # files failed
            # it's a quite a bit of work to simplify further because errors may or may not have path, span, etc.
            error_stats = (
                f"{len(self.semgrep_structured_errors)} files could not be analyzed"
            )
            final_error = self.semgrep_structured_errors[-1]
        self.final_raise(final_error, error_stats)

    @classmethod
    def save_output(cls, destination: str, output: str) -> None:
        if is_url(destination):
            cls.post_output(destination, output)
        else:
            if Path(destination).is_absolute():
                save_path = Path(destination)
            else:
                base_path = config_resolver.get_base_path()
                save_path = base_path.joinpath(destination)
            # create the folders if not exists
            save_path.parent.mkdir(parents=True, exist_ok=True)
            with save_path.open(mode="w") as fout:
                fout.write(output)

    @classmethod
    def post_output(cls, output_url: str, output: str) -> None:
        import requests  # here for faster startup times

        logger.info(f"posting to {output_url}...")
        try:
            r = requests.post(output_url, data=output, timeout=10)
            logger.debug(f"posted to {output_url} and got status_code:{r.status_code}")
        except requests.exceptions.Timeout:
            raise SemgrepError(f"posting output to {output_url} timed out")

    def build_output(
        self, color_output: bool, per_finding_max_lines_limit: Optional[int]
    ) -> str:
        output_format = self.settings.output_format
        debug_steps = None
        if output_format == OutputFormat.JSON_DEBUG:
            debug_steps = self.debug_steps_by_rule
        if output_format.is_json():
            return build_output_json(
                self.rule_matches,
                self.semgrep_structured_errors,
                self.all_targets,
                self.settings.json_stats,
                self.settings.json_time,
                self.filtered_rules,
                self.match_time_matrix,
                self.profiler,
                debug_steps,
            )
        elif output_format == OutputFormat.JUNIT_XML:
            return build_junit_xml_output(self.rule_matches, self.rules)
        elif output_format == OutputFormat.SARIF:
            return build_sarif_output(
                self.rule_matches, self.rules, self.semgrep_structured_errors
            )
        elif output_format == OutputFormat.EMACS:
            return build_emacs_output(self.rule_matches, self.rules)
        elif output_format == OutputFormat.VIM:
            return build_vim_output(self.rule_matches, self.rules)
        elif output_format == OutputFormat.TEXT:
            return "\n".join(
                list(
                    build_normal_output(
                        self.rule_matches, color_output, per_finding_max_lines_limit
                    )
                )
            )
        else:
            # https://github.com/python/mypy/issues/6366
            raise RuntimeError(
                f"Unhandled output format: {type(output_format).__name__}"
            )
