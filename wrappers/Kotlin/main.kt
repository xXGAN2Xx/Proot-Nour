import java.io.File;import java.net.URI;import java.nio.file.*;import kotlin.system.exitProcess
fun main(){val n="nour.sh";val u="https://raw.githubusercontent.com/xXGAN2Xx/Proot-Nour/refs/heads/main/nour.sh";val f=File(n)
try{if(!f.exists()||try{URI(u).toURL().readText()!=f.readText()}catch(e:Exception){true}){URI(u).toURL().openStream().use{Files.copy(it,f.toPath(),StandardCopyOption.REPLACE_EXISTING)};f.setExecutable(true)}
if(f.canExecute()&&ProcessBuilder("bash",f.absolutePath).inheritIO().start().waitFor()==0)exitProcess(0)}catch(e:Exception){e.printStackTrace()}}
