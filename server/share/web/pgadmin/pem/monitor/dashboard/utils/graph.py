##########################################################################
#
# Postgres Enterprise Manager
#
# Copyright (C) 2016 - 2025, EnterpriseDB Corporation. All rights reserved.
#
##########################################################################

""" Graph Rendering Functions."""

from xml.etree.ElementTree import Element, SubElement
from pgadmin.pem.misc.error import prettify
from flask_babel import gettext


# Render a property list table of data. Yeah, I know it's not a graph.
def graph_render_proplist(results, columns, rows, tableName='', sortable=True):

    cols = len(columns)

    div = Element('div', attrib={'style': 'overflow:auto;'})

    table = SubElement(
        div, 'table', attrib={
            'id': tableName, 'class': 'TableLayout',
            'style': 'table-layout:fixed;width:100%'
        }
    )

    # Add the header section, describing the columns
    thead = SubElement(table, 'thead')
    tr = SubElement(thead, 'tr')

    # Column 1
    th = SubElement(tr, 'th')
    th.attrib['style'] = 'width: 25%;'
    th.text = gettext("Name")

    # End h4, th

    # Column 2
    th1 = SubElement(tr, 'th')
    th1.attrib['style'] = 'width: 25%;'
    th1.attrib['data-sort-method'] = 'natural'

    h4_1 = SubElement(th1, 'h4', attrib={'class': 'pem-not-sorted'})

    # if not column_header[1]:
    #    h4.text = gettext("Value")
    # else:
    #    h4.text = nl2br(column_header[1])
    h4_1.text = gettext("Value")
    # End h4, th, tr, thead

    # Loop through the rows, outputing each value in a list.
    tbody = SubElement(table, 'tbody')

    for col in range(0, cols):
        tr = SubElement(tbody, 'tr')

        # Use the appropriate style for the row
        if (col % 2 == 0):
            tr.attrib['class'] = 'ReportDetailsEvenDataRow'
        else:
            tr.attrib['class'] = 'ReportDetailsOddDataRow'

        # Write the Column Name
        td = SubElement(tr, 'td')
        td.attrib['class'] = 'ReportTableValueCell'
        td.attrib['style'] = 'white-space: normal; word-wrap: break-word; ' \
            'vertical-align: text-top;'

        column_name = str(columns[col])

        if column_name is None:
            column_name = ""
        td.text = nl2br(column_name)
        # End td

        # Write the value
        td1 = SubElement(tr, 'td')
        td1.attrib['class'] = 'ReportTableValueCell'
        td1.attrib['style'] = 'white-space:normal;word-wrap:break-word;'

        if rows > 0:
            column_value = results[0][col]
            if column_value is None:
                column_value = ""
        else:
            column_value = ""

        td1.text = nl2br(str(column_value))
        # End td, tr

    return prettify(div)

# Redefined here because of circular dependency


def nl2br(string, isAttr=False):
    if isAttr:
        return string.replace('\n', '@@PEMEDBATBR@@\n')
    return string.replace('\n', '@@PEMEDBBR@@\n')
