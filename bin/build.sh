#!/bin/bash
source ${dic[cfg_devops_bin_path]}/log.sh

function check_env_by_cmd_v() {
        command -v $1 >/dev/null 2>&1 || { error "Need to install ##$1## command first and run this script again.";
 }
}

function parse_params() {
        case "$1" in
	-v) echo "devops version 1.1.5" ; exit 1;;
        --version) echo "devops version 1.1.5" ; exit 1;;
        -h)  echo "the help of devops ,to do" ; exit 1;;
        *) 
                dic[cmd_1]=$1
                shift 1
                case "$1" in
                -h)  echo "the help of first cmd ,to do" ; exit 1;;
                *)
                        dic[cmd_2]=$1
                        shift 1
                        while [ true ] ; do
                                if [[ $1 == -* ]];then
                                        case "$1" in
                                        --build-tool) dic[opt_build_tool]=$2; shift 2;;
                                        --git-url) dic[opt_git_url]=$2;  shift 2;;
                                        --svn-url) dic[opt_svn_url]=$2; shift 2;;
                                        --java-opts) dic[opt_java_opts]=$2; shift 2;;
                                        --dockerfile) dic[opt_dockerfile]=$2; shift 2;;
					--template) dic[opt_template]=$2; shift 2;;
					--git-branch) dic[opt_git_branch]=$2; shift 2;;
					--build-cmds) dic[opt_build_cmds]=$2; shift 2;;
                                        --build-env) dic[opt_build_env]=$2; shift 2;;
                                        *)         echo $2 echo "unknown parameter or command $1 ." ; exit 1 ; break;;
                                        esac
                                else
                                        dic[cmd_3]=$1
                                        shift 1
                                        break
                                fi
                        done

                ;;  esac
        ;; esac
}

function run() {
        case ${dic[cmd_1]} in
        run) 
                if test -n ${dic[cmd_2]}; then
                        ${dic[cmd_2]}
                else
                        echo "run need be followed by a cammand"; exit 1
                fi
         ;;
        *) echo "cannot find the cammand ${dic[cmd_1]}"; exit 1 ; ;;
	esac
}

function check_post_parmas() {
 	if [[ -z ${dic[cmd_3]} ]];then
                echo "job name can not be null ## $1 ##."; exit 1;
	 fi
	dic[cmd_job_name]=${dic[cmd_3]} 
	dic[cfg_temp_dir]=/tmp/devops/${dic[cmd_job_name]}
	rm -rf ${dic[cfg_temp_dir]}
}


function java() {
        #检测前置参数
	check_post_parmas
	#从版本管理工具加载代码
	scm 
	#执行java构建
	java_build 
	#复制dockerfile文件
	cp_dockerfile 
	#构建java镜像
	java_build_image 
	#渲染模板
	render_template 
	#执行部署
	deploy 
	#清除冗余镜像
	prune

}

function vue() {

	check_post_parmas

	scm 

	vue_build 

	cp_dockerfile 

	vue_build_image 

	render_template 

	deploy 

	prune 

}

function scm() {
	cfg_temp_dir=${dic[cfg_temp_dir]}
	opt_git_url=${dic[opt_git_url]}
	opt_git_branch=${dic[opt_git_branch]}
	opt_svn_url=${dic[opt_svn_url]}

	if [ -n "$opt_git_url" ]; then 
		check_env_by_cmd_v git

                info "scm 使用 git 拉取代码"
		#克隆代码
		if -n "${opt_git_branch}" ; then
			git clone -b --single-branch ${opt_git_branch} $opt_git_url  $cfg_temp_dir
		else 
		        git clone --single-branch $opt_git_url  $cfg_temp_dir
		fi
		cd $cfg_temp_dir
		#生成日期和git日志版本后六位
		date=`date +%Y-%m-%d_%H-%M-%S`
		last_log=`git log --pretty=format:%h | head -1`
		echo -e "\n关键变量值:\n last_log:$last_log\n"
		dic[tmp_docker_image_suffix]="${date}_${last_log}"
	elif [ -n "$opt_svn_url" ]; then 
		check_env_by_cmd_v svn
		info 'scm 使用 svn 拉取代码'
		svn checkout $opt_svn_url $cfg_temp_dir
		cd $cfg_temp_dir
		date=`date +%Y-%m-%d_%H-%M-%S`
		tmp_log=`svn log | head -2 | tail -1`
		last_log=${tmp_log%% *}
		echo -e "\n关键变量值:\n last_log:$last_log\n"
                dic[tmp_docker_image_suffix]="${date}_${last_log}"
	else 
		echo "--git-url and --svn-url must has one"; exit 1;
	fi
}

function java_build() {
	cfg_temp_dir=${dic[cfg_temp_dir]}
	cmd_job_name=${dic[cmd_job_name]}
	opt_build_tool=${dic[opt_build_tool]}
	opt_build_cmds=${dic[opt_build_cmds]}

	module_path=`find $cfg_temp_dir/* -type d  -name  ${cmd_job_name}`
        if test -z "$module_path"; then module_path=$cfg_temp_dir; fi
        echo -e "\n关键变量值:\n module_path:$module_path\n"


	case "$opt_build_tool"  in
	gradle)
		check_env_by_cmd_v gradle
	
		#构建代码
		if test -n "$opt_build_cmds" ;then
			d $module_path && $opt_build_cmds
        	else
			cd $module_path && gradle -x test clean build
        	fi
		dic[tmp_build_dist_path]=$module_path/build/libs
	 ;;
	maven)
		check_env_by_cmd_v mvn
		 #构建代码
                if test -n "$opt_build_cmds" ;then
			cd $module_path && ${opt_build_cmds}
		else
			cd $module_path && mvn clean -Dmaven.test.skip=true  compile package -U -am
		fi
		dic[tmp_build_dist_path]=$module_path/target
       	#to do
	 ;;
	*) echo "java project only support gradle or maven build"; exit 1; ;;
    	esac
}

function vue_build() {
        cfg_temp_dir=${dic[cfg_temp_dir]}
        cmd_job_name=${dic[cmd_job_name]}
	opt_build_cmds=${dic[opt_build_cmds]}
	opt_build_env=${dic[opt_build_env]}	

	check_env_by_cmd_v npm	

        module_path=`find $cfg_temp_dir/* -type d  -name  ${cmd_job_name}`
        if test -z "$module_path"; then module_path=$cfg_temp_dir; fi
	if test -n "$opt_build_cmds" ;then
		cd $module_path &&  npm --unsafe-perm install && $opt_build_cmds
	else
		if test -n "$opt_build_env" ;then
			cd $module_path && npm --unsafe-perm install && npm run build:$opt_build_env
		else
			cd $module_path && npm --unsafe-perm install && npm run build
		fi
	fi
	dic[tmp_build_dist_path]=$module_path/dist
}

function cp_dockerfile() {
	opt_dockerfile=${dic[opt_dockerfile]}
	cfg_dockerfile_path=${dic[cfg_dockerfile_path]}
	cfg_enable_dockerfiles=${dic[cfg_enable_dockerfiles]}
	tmp_build_dist_path=${dic[tmp_build_dist_path]}
	echo "opt-dockerfile ${opt_dockerfile}"
	if test -n "${opt_dockerfile}"
	then
		echo " into opt-dockerfile"
   		cp $cfg_dockerfile_path/${opt_dockerfile}-dockerfile ${tmp_build_dist_path}/dockerfile
	else
		dockerfiles=(${cfg_enable_dockerfiles//,/ })
		echo "关键变量:cfg_enable_dockerfiles:$cfg_enable_dockerfiles,dockerfiles:$dockerfiles"
		is_has_enable_docker_file=false
		for dockerfile in ${dockerfiles[@]} ;do
			if [[ $module_name == $dockerfile ]]
			then
			   cp $cfg_dockerfile_path/${dockerfile}-dockerfile ${tmp_build_dist_path}/dockerfile
			   is_has_enable_docker_file=true
			fi
		done
		if [ "$is_has_enable_docker_file" = false ]; then
		   cp $cfg_dockerfile_path/dockerfile ${tmp_build_dist_path}/
		fi
	fi
}


function java_build_image() {
	cmd_job_name=${dic[cmd_job_name]}
        opt_java_opts=${dic[opt_java_opts]}
	cfg_harbor_address=${dic[cfg_harbor_address]}
	cfg_harbor_project=${dic[cfg_harbor_project]}
	tmp_build_dist_path=${dic[tmp_build_dist_path]}
	tmp_docker_image_suffix=${dic[tmp_docker_image_suffix]}


	# 查找jar包名
	cd ${tmp_build_dist_path}
	jar_name=`ls | grep -v 'source'| grep ${cmd_job_name}`
	
	check_env_by_cmd_v docker

	# 构建镜像
	image_path=$cfg_harbor_address/$cfg_harbor_project/${cmd_job_name}_${tmp_docker_image_suffix}:latest
	docker build --build-arg jar_name=$jar_name\
	       --build-arg java_opts="opt_java_opts"\
	       --tag $image_path .

	#推送镜像
	docker push $image_path
	dic[tmp_image_path]=$image_path
}

function vue_build_image() {
	cmd_job_name=${dic[cmd_job_name]}
	cfg_harbor_address=${dic[cfg_harbor_address]}
	cfg_harbor_project=${dic[cfg_harbor_project]}
	tmp_build_dist_path=${dic[tmp_build_dist_path]}
	tmp_docker_image_suffix=${dic[tmp_docker_image_suffix]}


	# build临时目标路径
	cd ${tmp_build_dist_path}
	check_env_by_cmd_v docker
	# 构建镜像
	image_path=$cfg_harbor_address/$cfg_harbor_project/${cmd_job_name}_${tmp_docker_image_suffix}:latest
	echo "vue_build_image-->image_path: $image_path"
	tar -cf dist.tar *
	docker build -t $image_path .

	#推送镜像
	docker push $image_path
	dic[tmp_image_path]=$image_path
}


function render_template() {
	opt_template=${dic[opt_template]}
	cfg_devops_path=${dic[cfg_devops_path]}
	cfg_swarm_network=${dic[cfg_swarm_network]}
	cfg_template_path=${dic[cfg_template_path]}
	cfg_enable_templates=${dic[cfg_enable_templates]}
	cmd_job_name=${dic[cmd_job_name]}
	tmp_image_path=${dic[tmp_image_path]}


	cd $cfg_template_path
	gen_long_time_str=`date +%s%N`

	 #处理模板路由信息
	if test -n "${opt_template}"; then
		\cp ./${opt_template}-template.yml ./${gen_long_time_str}.yml
	else
		templates=(${cfg_enable_templates//,/ })
	        is_has_enable_template=false
	        for template in ${templates[@]}
	        do
	        if [[ $cmd_job_name == $template ]]
	        then
	           \cp ./$cmd_job_name-template.yml ./${gen_long_time_str}.yml
	           is_has_enable_template=true
       		fi
	        done
       		if [ "$is_has_enable_template" = false ]
        	then
            	\cp ./template.yml ./${gen_long_time_str}.yml
        	fi
	fi

	#执行替换
	sed -i "s#?module_name#${cmd_job_name}#g"  ./${gen_long_time_str}.yml
	sed -i "s#?image_path#${tmp_image_path}#g"  ./${gen_long_time_str}.yml
	sed -i "s#?network#${cfg_swarm_network}#g"  ./${gen_long_time_str}.yml

	#生成文件
	if [ ! -d "$cfg_devops_path/deploy" ];then
	mkdir -p $cfg_devops_path/deploy
	fi
	\mv ./${gen_long_time_str}.yml $cfg_devops_path/deploy/${cmd_job_name}.yml
}

function deploy() {
        cfg_devops_path=${dic[cfg_devops_path]}
	cfg_build_platform=${dic[cfg_build_platform]}
	cfg_swarm_stack_name=${dic[cfg_swarm_stack_name]}
	cmd_job_name=${dic[cmd_job_name]}
	#创建或者更新镜像
	if [ "$cfg_build_platform" = "KUBERNETES" ]
	then
		check_env_by_cmd_v kubectl
		echo "build_platform_k8s"
	    	kubectl apply -f  ${cfg_devops_path}/deploy/${cmd_job_name}.yml
	elif [ "$cfg_build_platform" = "DOCKER_SWARM" ]
	then
	    	echo "build_platform_docker_swarm"
	    	docker stack deploy -c ${cfg_devops_path}/deploy/${cmd_job_name}.yml ${cfg_swarm_stack_name}  --with-registry-auth
	else
		echo "build_platform_default"
		docker stack deploy -c ${cfg_devops_path}/deploy/${cmd_job_name}.yml ${cfg_swarm_stack_name} --with-registry-auth
	fi
}

function prune() {
	cfg_devops_path=${dic[cfg_devops_path]}
	cfg_temp_dir=${dic[cfg_temp_dir]}

	#删除源代码
	cd $cfg_devops_path
	rm -rf $cfg_temp_dir

	#!清除没有运行的无用镜像
	docker image prune -af --filter="label=maintainer=corp"
}
