package init.luobd;

import java.util.List;

/**
 * Word 表格实体，包含表格序号及行列数据。
 *
 * @param index 文档中表格的序号（从 0 开始）
 * @param rows  表格行数据，每行为一个单元格文本列表
 */
public record WordTable(int index, List<List<String>> rows) {
}
