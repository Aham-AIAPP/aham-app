# -*- coding: utf-8 -*-
"""
update_toc_export.py — 用 LibreOffice 的 UNO 接口：打开 docx → 更新所有目录/索引/页码域 → 导出 PDF

为什么需要它：目录(TOC)与页码是 Word 域，普通 `soffice --convert-to pdf` 不会填充它们，
导出的 PDF 目录会是空的。本脚本启动 headless LibreOffice，调 UNO 接口先更新域再导出。

用法：
    python scripts/update_toc_export.py 输入.docx [输出.pdf]
不带参数时，默认处理 examples/aham-word-demo.docx → examples/aham-word-demo.pdf
依赖：LibreOffice（提供 soffice 与 python-uno）。
"""
import os
import subprocess
import sys
import time


def main():
    if len(sys.argv) >= 2:
        in_docx = os.path.abspath(sys.argv[1])
    else:
        here = os.path.dirname(os.path.abspath(__file__))
        in_docx = os.path.abspath(os.path.join(here, "..", "examples", "aham-word-demo.docx"))
    out_pdf = os.path.abspath(sys.argv[2]) if len(sys.argv) >= 3 else os.path.splitext(in_docx)[0] + ".pdf"

    if not os.path.isfile(in_docx):
        print("找不到输入文件：", in_docx)
        sys.exit(1)

    soffice = "/usr/bin/soffice"
    if not os.path.isfile(soffice):
        for cand in ("/usr/bin/libreoffice", "/opt/libreoffice/program/soffice"):
            if os.path.isfile(cand):
                soffice = cand
                break

    proc = subprocess.Popen([
        soffice, "--headless", "--invisible", "--nocrashreport", "--nodefault",
        "--nofirststartwizard", "--nologo", "--norestore",
        "--accept=socket,host=localhost,port=2002;urp;StarOffice.ComponentContext",
    ])
    time.sleep(8)

    try:
        import uno
        from com.sun.star.beans import PropertyValue
        localContext = uno.getComponentContext()
        resolver = localContext.ServiceManager.createInstanceWithContext(
            "com.sun.star.bridge.UnoUrlResolver", localContext)
        ctx = resolver.resolve(
            "uno:socket,host=localhost,port=2002;urp;StarOffice.ComponentContext")
        smgr = ctx.ServiceManager
        desktop = smgr.createInstanceWithContext("com.sun.star.frame.Desktop", ctx)

        inprops = PropertyValue(); inprops.Name = "Hidden"; inprops.Value = True
        doc = desktop.loadComponentFromURL("file://" + in_docx, "_blank", 0, (inprops,))

        # 更新所有目录/索引
        indexes = doc.getDocumentIndexes()
        for i in range(indexes.getCount()):
            indexes.getByIndex(i).update()
        # 刷新文本字段（页码等）
        try:
            doc.getTextFields().refresh()
        except Exception:
            pass

        outprops = PropertyValue(); outprops.Name = "FilterName"; outprops.Value = "writer_pdf_Export"
        doc.storeToURL("file://" + out_pdf, (outprops,))
        doc.close(False)
        print("OK 已导出（目录已更新）：", out_pdf)
    except Exception as e:
        print("UNO_FAIL:", e)
        sys.exit(2)
    finally:
        proc.terminate()


if __name__ == "__main__":
    main()
