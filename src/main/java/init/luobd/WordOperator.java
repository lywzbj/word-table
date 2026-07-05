package init.luobd;

import org.apache.poi.xwpf.usermodel.IBody;
import org.apache.poi.xwpf.usermodel.XWPFDocument;
import org.apache.poi.xwpf.usermodel.XWPFTable;
import org.apache.poi.xwpf.usermodel.XWPFTableCell;
import org.apache.poi.xwpf.usermodel.XWPFTableRow;
import org.apache.xmlbeans.XmlCursor;
import org.apache.xmlbeans.XmlObject;
import org.openxmlformats.schemas.wordprocessingml.x2006.main.CTBookmark;
import org.openxmlformats.schemas.wordprocessingml.x2006.main.CTTbl;
import org.openxmlformats.schemas.wordprocessingml.x2006.main.CTTc;
import org.openxmlformats.schemas.wordprocessingml.x2006.main.CTRow;
import org.openxmlformats.schemas.wordprocessingml.x2006.main.CTRow;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Word 文档操作类。
 */
public class WordOperator {

    private static final Logger log = LoggerFactory.getLogger(WordOperator.class);

    private static final String NS_XPATH =
            "declare namespace w='http://schemas.openxmlformats.org/wordprocessingml/2006/main'; "
          + "declare namespace wps='http://schemas.microsoft.com/office/word/2010/wordprocessingShape'";

    /** 记录从文本框中提取的 XWPFTable 对应的原始 XmlObject，保存前用于同步修改。 */
    private final Map<XWPFTable, XmlObject> textBoxTableOriginals = new HashMap<>();

    /**
     * 从输入流中读取 Word 文档的所有表格实体，包括文本框内嵌套的表格。
     *
     * @param inputStream .docx 文件输入流，调用方负责关闭
     * @return 文档中所有表格的列表，按遍历顺序编号
     * @throws IOException 文档读取或解析失败时抛出
     */
    public List<WordTable> getTables(InputStream inputStream) throws IOException {
        List<WordTable> tables = new ArrayList<>();

        try (XWPFDocument document = new XWPFDocument(inputStream)) {
            for (XWPFTable table : document.getTables()) {
                tables.add(extractTable(table, tables.size()));
                collectNestedTables(table, tables);
            }
        }

        log.info("共提取 {} 个表格（含嵌套）", tables.size());
        return tables;
    }

    /**
     * 获取最外层（第一个）表格指定列中所有文本框内嵌套的表格，
     * 返回可直接修改的 {@link XWPFTable} 对象。
     * 适用于表格单元格内各嵌套一个文本框表格的场景。
     *
     * @param inputStream .docx 文件输入流，调用方负责关闭
     * @param columnIndex 列索引（从 0 开始）
     * @return 该列各单元格中嵌套表格的 XWPFTable 列表，未找到嵌套表格的单元格跳过
     * @throws IOException 文档读取或解析失败时抛出
     */
    public List<XWPFTable> getColumnNestedTables(InputStream inputStream, int columnIndex) throws IOException {
        try (XWPFDocument document = new XWPFDocument(inputStream)) {
            return getColumnNestedTables(document, 0, columnIndex);
        }
    }

    public List<XWPFTable> getColumnNestedTables(XWPFDocument document, int columnIndex) {
        return getColumnNestedTables(document, 0, columnIndex);
    }

    /**
     * 获取指定表格指定列中嵌套的表格（单元格直接子级或文本框内），
     * 返回可直接修改的 {@link XWPFTable}，文档保持打开以便保存。
     *
     * @param document   已打开的 XWPFDocument（不会关闭）
     * @param tableIndex 表格序号（从 0 开始）
     * @param columnIndex 列索引（从 0 开始）
     * @return 该列各单元格中嵌套表格的 XWPFTable 列表
     */
    public List<XWPFTable> getColumnNestedTables(XWPFDocument document, int tableIndex, int columnIndex) {
        List<XWPFTable> nestedTables = new ArrayList<>();

        List<XWPFTable> tables = document.getTables();
        if (tableIndex >= tables.size()) {
            log.warn("表格序号 {} 超出范围，文档共 {} 个顶层表格", tableIndex, tables.size());
            return nestedTables;
        }

        XWPFTable table = tables.get(tableIndex);
        for (XWPFTableRow row : table.getRows()) {
            List<XWPFTableCell> cells = row.getTableCells();
            if (columnIndex >= cells.size()) {
                continue;
            }
            XWPFTableCell cell = cells.get(columnIndex);
            List<XWPFTable> cellTables = cell.getTables();
            if (cellTables != null) {
                nestedTables.addAll(cellTables);
            }
            findTablesInTextBoxAsXWPF(cell.getCTTc(), cell, nestedTables);
        }

        log.info("表格[{}]第 {} 列共提取 {} 个嵌套表格", tableIndex, columnIndex, nestedTables.size());
        return nestedTables;
    }

    /** @deprecated 使用 {@link #getColumnNestedTables(XWPFDocument, int, int)} 以便保存修改后的文档 */
    @Deprecated
    public List<XWPFTable> getColumnNestedTables(InputStream inputStream, int tableIndex, int columnIndex) throws IOException {
        try (XWPFDocument document = new XWPFDocument(inputStream)) {
            return getColumnNestedTables(document, tableIndex, columnIndex);
        }
    }

    /**
     * 获取最外层表格指定单元格（行+列）中文本框内嵌套的表格。
     *
     * @param inputStream .docx 文件输入流，调用方负责关闭
     * @param rowIndex    行索引（从 0 开始）
     * @param columnIndex 列索引（从 0 开始）
     * @return 该单元格中嵌套表格的 XWPFTable 列表
     * @throws IOException 文档读取失败时抛出
     */
    public List<XWPFTable> getCellNestedTables(InputStream inputStream, int rowIndex, int columnIndex) throws IOException {
        try (XWPFDocument document = new XWPFDocument(inputStream)) {
            return getCellNestedTables(document, 0, rowIndex, columnIndex);
        }
    }

    public List<XWPFTable> getCellNestedTables(XWPFDocument document, int rowIndex, int columnIndex) {
        return getCellNestedTables(document, 0, rowIndex, columnIndex);
    }

    /**
     * 获取指定表格指定单元格中嵌套的表格（单元格直接子级或文本框内），
     * 返回可直接修改的 {@link XWPFTable}，文档保持打开以便保存。
     *
     * @param document   已打开的 XWPFDocument（不会关闭）
     * @param tableIndex  表格序号（从 0 开始）
     * @param rowIndex    行索引（从 0 开始）
     * @param columnIndex 列索引（从 0 开始）
     * @return 该单元格中嵌套表格的 XWPFTable 列表
     */
    public List<XWPFTable> getCellNestedTables(XWPFDocument document, int tableIndex, int rowIndex, int columnIndex) {
        List<XWPFTable> nestedTables = new ArrayList<>();

        List<XWPFTable> tables = document.getTables();
        if (tableIndex >= tables.size()) {
            log.warn("表格序号 {} 超出范围，文档共 {} 个顶层表格", tableIndex, tables.size());
            return nestedTables;
        }

        XWPFTable table = tables.get(tableIndex);
        if (rowIndex >= table.getRows().size()) {
            log.warn("行序号 {} 超出范围，表格共 {} 行", rowIndex, table.getRows().size());
            return nestedTables;
        }

        XWPFTableRow row = table.getRow(rowIndex);
        List<XWPFTableCell> cells = row.getTableCells();
        if (columnIndex >= cells.size()) {
            log.warn("列序号 {} 超出范围，该行共 {} 列", columnIndex, cells.size());
            return nestedTables;
        }

        XWPFTableCell cell = cells.get(columnIndex);
        List<XWPFTable> cellTables = cell.getTables();
        if (cellTables != null) {
            nestedTables.addAll(cellTables);
        }
        findTablesInTextBoxAsXWPF(cell.getCTTc(), cell, nestedTables);

        log.info("表格[{}]单元格[{},{}]共提取 {} 个嵌套表格", tableIndex, rowIndex, columnIndex, nestedTables.size());
        return nestedTables;
    }

    /** @deprecated 使用 {@link #getCellNestedTables(XWPFDocument, int, int, int)} 以便保存修改后的文档 */
    @Deprecated
    public List<XWPFTable> getCellNestedTables(InputStream inputStream, int tableIndex, int rowIndex, int columnIndex) throws IOException {
        try (XWPFDocument document = new XWPFDocument(inputStream)) {
            return getCellNestedTables(document, tableIndex, rowIndex, columnIndex);
        }
    }

    /**
     * 读取文档中所有文本框的文本内容（含表格、页眉页脚中的文本框）。
     *
     * @param inputStream .docx 文件输入流，调用方负责关闭
     * @return 每个文本框的文本内容列表
     * @throws IOException 文档读取失败时抛出
     */
    public List<String> getTextBoxContents(InputStream inputStream) throws IOException {
        try (XWPFDocument document = new XWPFDocument(inputStream)) {
            return getTextBoxContents(document);
        }
    }

    /**
     * 读取文档中所有文本框的文本内容，文档保持打开以便后续操作。
     */
    public List<String> getTextBoxContents(XWPFDocument document) {
        List<String> contents = new ArrayList<>();
        XmlObject body = document.getDocument().getBody();
        XmlObject[] txbxContents = body.selectPath(NS_XPATH + ".//w:txbxContent");
        if (txbxContents == null) {
            return contents;
        }

        for (XmlObject txbx : txbxContents) {
            StringBuilder text = new StringBuilder();
            XmlObject[] textRuns = txbx.selectPath(
                    "declare namespace w='http://schemas.openxmlformats.org/wordprocessingml/2006/main'; "
                  + ".//w:t");
            if (textRuns != null) {
                for (XmlObject t : textRuns) {
                    try (XmlCursor c = t.newCursor()) {
                        text.append(c.getTextValue());
                    }
                }
            }
            contents.add(text.toString());
        }

        log.info("共提取 {} 个文本框内容", contents.size());
        return contents;
    }

    public List<XWPFTable> getTextBoxTables(InputStream inputStream) throws IOException {
        try (XWPFDocument document = new XWPFDocument(inputStream)) {
            return getTextBoxTables(document);
        }
    }

    /**
     * 读取文档中所有文本框内嵌套的表格，文档保持打开以便保存。
     */
    public List<XWPFTable> getTextBoxTables(XWPFDocument document) {
        List<XWPFTable> tables = new ArrayList<>();
        findTablesInTextBoxAsXWPF(document.getDocument().getBody(), document, tables);
        log.info("共提取 {} 个文本框内表格", tables.size());
        return tables;
    }

    /**
     * 将文档另存到指定路径。
     *
     * @param document 要保存的 XWPFDocument（需保持打开状态）
     * @param filePath 目标文件路径
     * @throws IOException 写入失败时抛出
     */
   public void saveDocument(XWPFDocument document, String filePath) throws IOException {
       syncTextBoxTables();
       try (FileOutputStream fos = new FileOutputStream(filePath)) {
           document.write(fos);
       }
        log.info("文档已保存至: {}", filePath);
    }

    /** 将文本框内表格的修改同步回原文档树。 */
    private void syncTextBoxTables() {
        for (Map.Entry<XWPFTable, XmlObject> entry : textBoxTableOriginals.entrySet()) {
            entry.getValue().set(entry.getKey().getCTTbl());
        }
        log.debug("已同步 {} 个文本框表格", textBoxTableOriginals.size());
    }

    /**
     * 将表格所有行列数据打印到控制台。
     *
     * @param table 要打印的 XWPFTable 对象
     */
    public void printTable(XWPFTable table) {
        for (int i = 0; i < table.getRows().size(); i++) {
            XWPFTableRow row = table.getRow(i);
            for (int j = 0; j < row.getTableCells().size(); j++) {
                System.out.printf("[%d,%d] %s%n", i, j, row.getCell(j).getText());
            }
        }
    }

    /**
     * 根据模板行中的字段名，将 Map 列表数据渲染到表格中。
     *
     * <p>模板行每个单元格中的文本作为字段名，与 Map 的 key 对应。
     * 第一个数据行直接复用模板行，后续数据行通过拷贝模板行结构以保持样式一致。
     *
     * @param table        目标表格
     * @param dataStartRow 模板行所在的行索引（数据从该行开始渲染）
     * @param data         数据列表，每个 Map 对应一行
     */
    public void fillTableData(XWPFTable table, int dataStartRow, List<Map<String, String>> data) {
        if (data == null || data.isEmpty()) {
            return;
        }

        // 1. 解析模板行，建立列索引 → 字段名的映射
        XWPFTableRow templateRow = table.getRow(dataStartRow);
        Map<Integer, String> colToField = new LinkedHashMap<>();
        for (int c = 0; c < templateRow.getTableCells().size(); c++) {
            String fieldName = templateRow.getCell(c).getText().trim();
            colToField.put(c, fieldName);
        }

       // 2. 清空模板行内容
       for (int c : colToField.keySet()) {
           // 绕过 XWPFTableCell.setText() 的 XmlBeans 缓存问题，直接重置 CT 层
           var ctTc = table.getCTTbl().getTrList().get(dataStartRow).getTcList().get(c);
            // 用 removeP 逐项删除而非 setPArray(null)，因为 getPList() 有缓存
            while (ctTc.sizeOfPArray() > 0) {
                ctTc.removeP(0);
            }
           ctTc.addNewP().addNewR().addNewT().setStringValue("");
       }

        // 3. 准备模板行的 CT 引用用于后续行复制
        CTTbl ctTbl = table.getCTTbl();
        CTRow templateCtRow = ctTbl.getTrList().get(dataStartRow);

       // 4. 填充第一行（模板行）
       Map<String, String> firstRow = data.get(0);
       for (Map.Entry<Integer, String> entry : colToField.entrySet()) {
           int c = entry.getKey();
           var ctTc = table.getCTTbl().getTrList().get(dataStartRow).getTcList().get(c);
            while (ctTc.sizeOfPArray() > 0) {
                ctTc.removeP(0);
            }
           ctTc.addNewP().addNewR().addNewT().setStringValue(
               firstRow.getOrDefault(entry.getValue(), ""));
       }

      // 5. 后续数据行：在断开副本上设置文本，再插入表格
      for (int i = 1; i < data.size(); i++) {
          Map<String, String> rowData = data.get(i);
          CTRow newCtRow = (CTRow) templateCtRow.copy();

          ctTbl.getTrList().add(dataStartRow + i, newCtRow);

           // 从 trList 取回已挂载的行再修改，避免 copy 出来的独立对象在 add 时被 parent 重写
           CTRow addedRow = ctTbl.getTrList().get(dataStartRow + i);
           setCtCellTextFallback(addedRow, colToField, rowData);
      }

        log.info("表格数据填充完成，从第 {} 行开始共渲染 {} 行", dataStartRow, data.size());
    }

    /**
     * CT 层回退：当 XWPFTableRow 不可用时，直接操作 CT 对象设置文本。
     * 先清空所有已有文本，再将第一段的值设为目标值，确保即使 copy 后的结构与预期不同也能正确写入。
     */
   private void setCtCellTextFallback(CTRow ctRow, Map<Integer, String> colToField, Map<String, String> rowData) {
       var tcList = ctRow.getTcList();
       for (Map.Entry<Integer, String> entry : colToField.entrySet()) {
           int col = entry.getKey();
           String value = rowData.getOrDefault(entry.getValue(), "");
           if (col >= tcList.size()) continue;
           var ctTc = tcList.get(col);

            // 逐项删除段落以正确更新 XmlBeans 内部缓存
            while (ctTc.sizeOfPArray() > 0) {
                ctTc.removeP(0);
            }
           ctTc.addNewP().addNewR().addNewT().setStringValue(value);
       }
   }

    /** 提取顶层表格（使用 POI 高级 API）。 */
    private WordTable extractTable(XWPFTable table, int index) {
        List<List<String>> rows = new ArrayList<>();
        for (XWPFTableRow row : table.getRows()) {
            List<String> cells = new ArrayList<>();
            for (XWPFTableCell cell : row.getTableCells()) {
                cells.add(cell.getText());
            }
            rows.add(cells);
        }
        return new WordTable(index, rows);
    }

    /** 递归查找顶层表格各单元格的文本框里是否嵌套了表格。 */
    private void collectNestedTables(XWPFTable table, List<WordTable> collector) {
        for (XWPFTableRow row : table.getRows()) {
            for (XWPFTableCell cell : row.getTableCells()) {
                findTablesInTextBox(cell.getCTTc(), collector);
            }
        }
    }

    /**
     * 在任意 XmlObject 子树的文本框（w:txbxContent）中查找 w:tbl 元素，
     * 解析为 WordTable 并递归其单元格。
     */
    private void findTablesInTextBox(XmlObject node, List<WordTable> collector) {
        XmlObject[] tbls = node.selectPath(NS_XPATH + ".//w:txbxContent/w:tbl");
        if (tbls == null || tbls.length == 0) {
            return;
        }

        for (XmlObject tblObj : tbls) {
            if (isInsideFallback(tblObj)) {
                continue;
            }
            CTTbl ctTbl;
            try {
                ctTbl = CTTbl.Factory.parse(tblObj.xmlText());
            } catch (Exception e) {
                log.warn("解析文本框内嵌套表格失败，跳过", e);
                continue;
            }

            collector.add(parseCTTbl(ctTbl, collector.size()));

            // 递归该嵌套表格的单元格
            for (CTRow ctTr : ctTbl.getTrList()) {
                for (CTTc ctTc : ctTr.getTcList()) {
                    findTablesInTextBox(ctTc, collector);
                }
            }
        }
    }

    /**
     * 通过书签名称获取书签所在的表格。
     *
     * @param bookmarkName 书签名称
     * @param inputStream  .docx 文件输入流，调用方负责关闭
     * @return 书签所在的 XWPFTable，未找到则返回 null
     * @throws IOException 文档读取失败时抛出
     */
    public XWPFTable getTableByBookmark(String bookmarkName, InputStream inputStream) throws IOException {
        try (XWPFDocument document = new XWPFDocument(inputStream)) {
            return getTableByBookmark(document, bookmarkName);
        }
    }

    /**
     * 通过书签名称获取表格，文档保持打开以便保存。
     */
    public XWPFTable getTableByBookmark(XWPFDocument document, String bookmarkName) {
        CTBookmark bookmark = findBookmark(document, bookmarkName);
        if (bookmark == null) {
            log.warn("未找到书签: {}", bookmarkName);
            return null;
        }

        XmlCursor cursor = bookmark.newCursor();
        try {
            while (cursor.toParent()) {
                XmlObject parent = cursor.getObject();
                if (parent instanceof CTTbl ctTbl) {
                    return new XWPFTable(ctTbl, document);
                }
            }
        } finally {
            cursor.dispose();
        }

        log.warn("书签 {} 不在任何表格内", bookmarkName);
        return null;
    }

    private CTBookmark findBookmark(XWPFDocument document, String name) {
        for (CTBookmark bm : document.getDocument().getBody().getBookmarkStartList()) {
            if (name.equals(bm.getName())) {
                return bm;
            }
        }
        return null;
    }

    /**
     * 在任意 XmlObject 子树的文本框（w:txbxContent）中查找 w:tbl 元素，
     * 包装为 {@link XWPFTable}（以传入的 cell 作为 IBody）。
     */
    private void findTablesInTextBoxAsXWPF(XmlObject node, IBody body, List<XWPFTable> collector) {
        XmlObject[] tbls = node.selectPath(NS_XPATH + ".//w:txbxContent/w:tbl");
        if (tbls == null || tbls.length == 0) {
            return;
        }

        for (XmlObject tblObj : tbls) {
            if (isInsideFallback(tblObj)) {
                log.debug("跳过 mc:Fallback 中的冗余表格");
                continue;
            }
            try {
                CTTbl ctTbl = CTTbl.Factory.parse(tblObj.xmlText());
                XWPFTable nestedTable = new XWPFTable(ctTbl, body);
                textBoxTableOriginals.put(nestedTable, tblObj);
                collector.add(nestedTable);
            } catch (Exception e) {
                log.warn("解析文本框内嵌套表格失败，跳过", e);
            }
        }
    }

    /** 检查 XmlObject 是否在 mc:AlternateContent/mc:Fallback 兼容性副本中。 */
    private boolean isInsideFallback(XmlObject obj) {
        try (XmlCursor c = obj.newCursor()) {
            while (c.toParent()) {
                if (c.getName() == null) {
                    continue;
                }
                if ("Fallback".equals(c.getName().getLocalPart())
                        && "http://schemas.openxmlformats.org/markup-compatibility/2006"
                                .equals(c.getName().getNamespaceURI())) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * 在单元格中直接查找 w:tbl 子元素（非文本框内），包装为 {@link XWPFTable}。
     */
    private void findDirectTablesInCell(XWPFTableCell cell, List<XWPFTable> collector) {
        CTTc ctTc = cell.getCTTc();
        XmlObject[] tbls = ctTc.selectPath(
                "declare namespace w='http://schemas.openxmlformats.org/wordprocessingml/2006/main'; "
              + "$this./w:tbl");
        if (tbls == null || tbls.length == 0) {
            return;
        }

        for (XmlObject tblObj : tbls) {
            try {
                CTTbl ctTbl = CTTbl.Factory.parse(tblObj.xmlText());
                collector.add(new XWPFTable(ctTbl, cell));
            } catch (Exception e) {
                log.warn("解析单元格内直接嵌套表格失败，跳过", e);
            }
        }
    }

    /** 将 CTTbl 转为 WordTable（无 XWPF 高层 API 依赖）。 */
    private WordTable parseCTTbl(CTTbl ctTbl, int index) {
        List<List<String>> rows = new ArrayList<>();
        for (CTRow ctTr : ctTbl.getTrList()) {
            List<String> cells = new ArrayList<>();
            for (CTTc ctTc : ctTr.getTcList()) {
                StringBuilder text = new StringBuilder();
                ctTc.getPList().forEach(p ->
                    p.getRList().forEach(r ->
                        r.getTList().forEach(t -> text.append(t.getStringValue()))
                    )
                );
                cells.add(text.toString());
            }
            rows.add(cells);
        }
        return new WordTable(index, rows);
    }
}
