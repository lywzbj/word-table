package init.luobd;

import java.io.File;
import java.io.FileInputStream;
import java.util.List;
import java.util.Map;

import org.apache.poi.xwpf.usermodel.XWPFDocument;
import org.apache.poi.xwpf.usermodel.XWPFTable;
import org.apache.poi.xwpf.usermodel.XWPFTableCell;
import org.apache.poi.xwpf.usermodel.XWPFTableRow;

/**
 *
 * Hello world!
 */
public class App {
    public static void main(String[] args) {
        WordOperator wordOperator = new WordOperator();
        File file = new File("/Users/luoyu/table3.docx");
        try (  XWPFDocument doc = new XWPFDocument(new FileInputStream("/Users/luoyu/table3.docx"))) {
            List<XWPFTable> tables = wordOperator.getCellNestedTables(doc, 0, 1);
            List<Map<String, String>> data = List.of(
                    Map.of("name", "张三", "age", "28", "dept", "研发部"),
                    Map.of("name", "李四", "age", "32", "dept", "市场部"),
                    Map.of("name", "王五", "age", "25", "dept", "研发部")
            );

            XWPFTable xwpfTable = tables.get(0);


           wordOperator.printTable(xwpfTable);


           wordOperator.fillTableData(tables.get(0),0,data);



            wordOperator.saveDocument(doc, "/Users/luoyu/table3_output.docx");






        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
