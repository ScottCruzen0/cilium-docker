package tmpl

import (
    "text/template"
    "tool/cli"
    "tool/file"
    "encoding/json"
)

command: tmpl: {
    _args: {
        json:           string @tag(json)
        filename:       string @tag(filename)
    }

    _contents: contents: string
    _contents: file.Read & { filename: _args.filename }

    _text: template.Execute(_contents.contents, json.Unmarshal(_args.json))

    output: cli.Print & { text: _text }
}
