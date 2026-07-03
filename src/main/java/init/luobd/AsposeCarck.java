package init.luobd;

import javassist.*;
import java.io.*;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import java.util.jar.JarOutputStream;

public class AsposeCarck {
    public static void main(String[] args) throws Exception {
        String property = System.getProperty("user.dir");
//        String jarPath =property+ "/src/main/resources/lib/aspose-pdf-22.4.jar";
        // 这个是jar包的存放路径
     //   String jarPath =property+ "/src/main/resources/lib/aspose-pdf-22.7.1.jar";
        // 破解方法
    //    crack(jarPath);
       // modifyWordsJar();
    }

    private static void crack(String jarName) {
        try {
            ClassPool.getDefault().insertClassPath(jarName);
            CtClass ctClass = ClassPool.getDefault().getCtClass("com.aspose.pdf.ADocument");
            CtMethod[] declaredMethods = ctClass.getDeclaredMethods();
            int num = 0;
            for (int i = 0; i < declaredMethods.length; i++) {
                if (num == 2) {
                    break;
                }
                CtMethod method = declaredMethods[i];
                CtClass[] ps = method.getParameterTypes();
                if (ps.length == 2
                        && method.getName().equals("lI")
                        && ps[0].getName().equals("com.aspose.pdf.ADocument")
                        && ps[1].getName().equals("int")) {
                    // 最多只能转换4页 处理
                    System.out.println(method.getReturnType());
                    System.out.println(ps[1].getName());
                    method.setBody("{return false;}");
                    num = 1;
                }
                if (ps.length == 0 && method.getName().equals("lt")) {
                    // 水印处理
                    method.setBody("{return true;}");
                    num = 2;
                }
            }
            File file = new File(jarName);
            ctClass.writeFile(file.getParent());
            disposeJar(jarName, file.getParent() + "/com/aspose/pdf/ADocument.class");
        } catch (NotFoundException e) {
            e.printStackTrace();
        } catch (CannotCompileException e) {
            e.printStackTrace();
        } catch (IOException e) {
            e.printStackTrace();
        }

    }

    private static void disposeJar(String jarName, String replaceFile) {
        List<String> deletes = new ArrayList<>();
        // 这个是22.* 版本的
        deletes.add("META-INF/37E3C32D.SF");
        deletes.add("META-INF/37E3C32D.RSA");

        // 这个是24.* 版本 使用这个
        deletes.add("META-INF/7DD91000.SF");
        deletes.add("META-INF/7DD91000.RSA");

        File oriFile = new File(jarName);
        if (!oriFile.exists()) {
            System.out.println("######Not Find File:" + jarName);
            return;
        }
        //将文件名命名成备份文件
        String bakJarName = jarName.substring(0, jarName.length() - 3) + "cracked.jar";
        //   File bakFile=new File(bakJarName);
        try {
            //创建文件（根据备份文件并删除部分）
            JarFile jarFile = new JarFile(jarName);
            JarOutputStream jos = new JarOutputStream(new FileOutputStream(bakJarName));
            Enumeration entries = jarFile.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = (JarEntry) entries.nextElement();
                if (!deletes.contains(entry.getName())) {
                    if (entry.getName().equals("com/aspose/pdf/ADocument.class")) {
                        System.out.println("Replace:-------" + entry.getName());
                        JarEntry jarEntry = new JarEntry(entry.getName());
                        jos.putNextEntry(jarEntry);
                        FileInputStream fin = new FileInputStream(replaceFile);
                        byte[] bytes = readStream(fin);
                        jos.write(bytes, 0, bytes.length);
                    } else {
                        jos.putNextEntry(entry);
                        byte[] bytes = readStream(jarFile.getInputStream(entry));
                        jos.write(bytes, 0, bytes.length);
                    }
                } else {
                    System.out.println("Delete:-------" + entry.getName());
                }
            }
            jos.flush();
            jos.close();
            jarFile.close();
        } catch (FileNotFoundException e) {
            e.printStackTrace();
        } catch (IOException e) {
            e.printStackTrace();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private static byte[] readStream(InputStream inStream) throws Exception {
        ByteArrayOutputStream outSteam = new ByteArrayOutputStream();
        byte[] buffer = new byte[1024];
        int len = -1;
        while ((len = inStream.read(buffer)) != -1) {
            outSteam.write(buffer, 0, len);
        }
        outSteam.close();
        inStream.close();
        return outSteam.toByteArray();
    }


    /**
     * 修改words jar包里面的校验
     */
    public static void modifyWordsJar() {

        String property = System.getProperty("user.dir");
        String parent = property + "/src/main/resources/lib/";
        String jarPath =parent+ "aspose-words-21.11-jdk17.jar";

        try {
            //这一步是完整的jar包路径,选择自己解压的jar目录
            ClassPool.getDefault().insertClassPath(jarPath);
            //获取指定的class文件对象
            CtClass zzZJJClass = ClassPool.getDefault().getCtClass("com.aspose.words.zzXDb");
            //从class对象中解析获取指定的方法
            CtMethod[] methodA = zzZJJClass.getDeclaredMethods("zzY0J");
            //遍历重载的方法
            for (CtMethod ctMethod : methodA) {
                CtClass[] ps = ctMethod.getParameterTypes();
                if (ctMethod.getName().equals("zzY0J")) {
                    System.out.println("ps[0].getName==" + ps[0].getName());
                    //替换指定方法的方法体
                    ctMethod.setBody("{this.zzZ3l = new java.util.Date(Long.MAX_VALUE);this.zzWSL = com.aspose.words.zzYeQ.zzXgr;zzWiV = this;}");
                }
            }
            //这一步就是将破译完的代码放在桌面上
            zzZJJClass.writeFile(parent);

            //获取指定的class文件对象
            CtClass zzZJJClassB = ClassPool.getDefault().getCtClass("com.aspose.words.zzYKk");
            //从class对象中解析获取指定的方法
            CtMethod methodB = zzZJJClassB.getDeclaredMethod("zzWy3");
            //替换指定方法的方法体
            methodB.setBody("{return 256;}");
            //这一步就是将破译完的代码放在桌面上
            zzZJJClassB.writeFile(parent);
        } catch (Exception e) {
            System.out.println("错误==" + e);
        }
    }


    String sourceFile = "D:\\b.doc";//输入的文件
    String targetFile = "D:\\转换后.pdf";//输出的文件
    /**
     * Word转PDF操作
     *
     * @param sourceFile 源文件
     * @param targetFile 目标文件
     */
    public static void doc2pdf(String sourceFile, String targetFile) {
        try {
            long old = System.currentTimeMillis();
            FileOutputStream os = new FileOutputStream(targetFile);
            com.aspose.words.Document
            com.aspose.words.Document doc = new com.aspose.words.Document(sourceFile);
            doc.save(os, com.aspose.words.SaveFormat.PDF);
            os.close();
            long now = System.currentTimeMillis();
            System.out.println("共耗时：" + ((now - old) / 1000.0) + "秒");  //转化用时
        } catch (Exception e) {
            e.printStackTrace();
        }
    }


}