Include Form

Class Form.JSON.SQL Extends %ZEN.Auxiliary.altJSONSQLProvider
{

ClassMethod WriteJSONFromSQL(sql As %String, conditionClass = "") As %Status
{
	#dim sc As %Status = $$$OK
	set provider = ..%New()
	set provider.maxRows = $$$MaxCacheInt
	set provider.%Format = $$$formatJSONSQL
	
	if ((##class(%Dictionary.CompiledClass).IDKEYExists(conditionClass)) && $$$webContext) {
		set sc = ..ParseWhere(%request.Get("filter"), %request.Get("collation"), conditionClass, .where)
		set sc = $$$ADDSC(sc, ..ParseOrderBy(%request.Get("orderby"), conditionClass, .orderBy))
		set sql = sql _ where _ orderBy
	} ElseIf (conditionClass'="") {
		set sc = $$$ERROR($$$GeneralError, "Condition class " _ conditionClass _ " does not exist")
	}
	return:$$$ISERR(sc) sc 
	
	set provider.sql = sql
	if $$$webContext {
		set provider.pageSize = %request.Get("size", 25)
		set provider.currPage = %request.Get("page", 1)
	}

	set nocount = %request.Get("nocount", $$$NO)
	
	set sc = provider.%DrawJSON(nocount)
	return sc
}

/// Parse where condition:
/// <example>w ##class(Form.JSON.SQL).ParseWhere("Text eq Admin Text neq 1", , "Form.Test.Simple", .out)</example>
/// result: out=" WHERE Text='Admin' AND Text='1'"
ClassMethod ParseWhere(input, collation As %String(VALUELIST=",SQLUPPER,EXACT") = "", conditionClass, Output condition) As %Status
{
	#dim sc As %Status = $$$OK
	kill condition
	set condition = ""
	set:$e(input,1)="(" input = $e(input,2,*-1)
	return:input="" sc
	
	set:collation'="" collation = "%" _ collation
	set condList = $LFS(input," ")
	set listLength= $LL(condList)
	
	if listLength#3'=0 {
		return $$$ERROR($$$GeneralError, "Incorrect number of filter arguments")
	}
	
	set condition = " WHERE "
	
	for i=1:3:listLength {
		set:i'=1 condition = condition _ " AND "
		set column = $lg(condList,i)
		set predicate = $lg(condList,i+1)
		set value = $TR($lg(condList,i+2),$c(9)," ") // replaces <TAB> in filter values eith whitespaces 
		set value = $TR(value,"'"";")
		
		set columnValid = ..ParseColumn(.column, conditionClass, .propertyClass)
		return:'columnValid $$$ERROR($$$GeneralError,"Filter column '" _column _ "' is not valid for " _ conditionClass)
		set:$system.SQL.IsReservedWord(column) column = """" _ column _ """"
		
		set value = ##class(Form.Util.Converter).jsonToLogical(propertyClass, value)
		
		set sqlpredicate = ..TranslatePredicate(predicate)
		if sqlpredicate="" {
			return $$$ERROR($$$GeneralError,"Incorrect filter predicate")
		}
		
		#define sq(%str) "'" _ %str _ "'"
		if sqlpredicate = "IN" {
			
			set valTemp = "("
			for j=1:1:$length(value, "~") {
				set curVal = $piece(value, "~", j)
				set curVal = $$$sq(curVal)
				set:curVal="'$$$NULL'" curVal = "NULL"
				set:((collation'="") && (curVal'="NULL")) curVal = collation _ "(" _ curVal _ ")"

				set valTemp = valTemp _ curVal
				set:j'=$length(value, "~") valTemp = valTemp _ ", "
			}
			set value = valTemp _ ")"
		} else {
			// bake ((value)) values as a (('value')) to help the optimizer
			if (($e(value,1,2)="((") && ($e(value,*-1,*)="))")) {
				set value = $e(value, 3,*-3)
				set value = $$$sq(value)
				set value = "((" _ value _ "))"
			} else {
				set value = $$$sq(value)
			}
			set:value="'$$$NULL'" value = "NULL"
		}

		if collation'="" {
			set:((value'="NULL") && (sqlpredicate '="IN")) value = collation _ "(" _ value _ ")"
			set column = collation _ "(" _ column _ ")"
		}
	
		set condition = condition _ column _ " " _ sqlpredicate _ " " _ value
	}
	return $$$OK
}

/// Is this column reference valid.
/// <example>w ##class(Form.JSON.SQL).ParseColumn("company->addrerss_City", "Form.Test.Person", .c)</example>
ClassMethod ParseColumn(ByRef column, conditionClass, Output finalPropertyClass) As %Boolean
{
	kill finalPropertyClass
	set column = $replace(column, "_", "->") // Serial references
	set columnOut = ""
	
	set length = $length(column,"->")
	for j = 1:1:length {
		// Determine current class context and property name
		set currentClass = $case(j, 1:conditionClass, :##class(Form.Property).getPropertyType(currentClass, currentProperty)) // first piece - conditionClass, otherwise - previous class
		set currentProperty = $piece(column,"->",j)
		
		// Last property may be an ID (which is not a %Dictionary.CompiledProperty cilumn, 
		// so quit from the for cycle
		if ((j=length) && ($zcvt(currentProperty, "U") = "ID")) {
			set columnOut = columnOut _ "ID"
			quit
		}
		
		// Property does not exist. Abort.
		if '##class(%Dictionary.CompiledProperty).IDKEYExists(currentClass, currentProperty) {
			return $$$NO
		}
		
		// Get property SQL name (usually equal to property name)
		set currentPropertySQLName = ##class(Form.Property).getPropertySQLName(currentClass, currentProperty)
		set:$system.SQL.IsReservedWord(currentPropertySQLName) currentPropertySQLName = """" _ currentPropertySQLName _ """"
		
		// Append property SQL name to resulting sql expression
		set columnOut = columnOut _ currentPropertySQLName
		
		// Append _ or -> separator if this is not a last column
		if j'=length {
			set propertyType = ##class(Form.Property).getPropertyType(currentClass, currentProperty)
			if $$$classIsSerial(propertyType) {
				set separator = "_"
			} else {
				set separator = "->"
			}
			set columnOut = columnOut _ separator
		}
	}
	set finalPropertyClass = ##class(Form.Property).getPropertyType(currentClass, currentProperty)
	set column = columnOut
	
	return $$$YES
}

/// Translate predicate from js into sql
ClassMethod TranslatePredicate(predicate = "") As %String
{
	q:predicate="" ""
	q:predicate="neq" "!="
	q:predicate="eq" "="
	q:predicate="gte" ">="
	q:predicate="gt" ">"
	q:predicate="lte" "<="
	q:predicate="lt" "<"
	q:predicate="startswith" "%STARTSWITH"
	q:predicate="contains" "["
	q:predicate="doesnotcontain" "NOT["
	q:predicate="in" "IN"
	q:predicate="is" "IS"
	q:predicate="isnot" "IS NOT"
	q:predicate="like" "LIKE"
	
	q ""
}

/// w ##class(Form.JSON.SQL).ParseOrderBy("Value desc", "Form.TestRef")
ClassMethod ParseOrderBy(input, class, Output condition) As %Status
{
	#dim sc As %Status = $$$OK
	kill condition
	
	// If input is an empty string use form FORMORDERBY parameter
	set:input="" input = $parameter(class, $$$orderByParam)
	set:input="" input = $parameter(class, $$$displayProp)
	set condition = ""
	return:input="" sc
	
	set descPos = $f(input, " desc")
	if descPos'=0 {
		set column = $e(input, 1, descPos-6) // 6 = $l("+desc")+1
	} else {
		set column=input
	}
	
	if ##class(%Dictionary.CompiledProperty).IDKEYExists(class, column) {
		set column = ##class(Form.Property).getPropertySQLName(class, column)
		set:$system.SQL.IsReservedWord(column) column = """" _ column _ """"
	} elseif $isValidNum(column, 0, 1) {
		/// nothing to do here
	} else {
		set sc = $$$ERROR($$$GeneralError, "Sorting column '" _ column _ "' does not exist")
		set column = "" // invalidate SQL jic
	}
	
	set condition = " ORDER BY " _ column _ $s(descPos'=0:" DESC",1:"")
	return sc
}

/// Draw JSON output.
/// nocount - do not output count of rows
Method %DrawJSON(nocount As %Boolean = {$$$NO}) As %Status [ Internal ]
{
	Set ..contentType = "array"
	// override base method to get information from SQL statement
	Set tSC = $$$OK
	Try {
		#; convert parameters to local array
		Set key = ..parameters.Next("")
		While (key'="") {
			Set value = ..parameters.GetAt(key).value
			Set tParms(key) = $$$ZENVAL(value)
			Set key = ..parameters.Next(key)
		}
		Set tOrigSQL = ..sql
		Set tSQL = ..sql

		If (..OnGetSQL '= "") {
			Set tSC = ..%OnGetSQL(.tParms,.tSQL)
			If $$$ISERR(tSC) {
				Quit
			}
			Set ..sql = tSQL
		}

		Set tInfo = ##class(%ZEN.Auxiliary.QueryInfo).%New()
		Merge tInfo.parms=tParms
		
		#Dim tRS As %Library.ResultSet
		Set tRS = ..%CreateResultSet(.tSC,tInfo)
		If $$$ISERR(tSC)||'$IsObject(tRS) {
			Quit
		}

		// find number and name of columns
		Kill tColInfo
		If tRS.%IsA("%Library.ResultSet") {
			Set tCols = tRS.GetColumnCount()
			For c = 1:1:tCols { 
				Set tColInfo(c,"name") = tRS.GetColumnHeader(c)
				Set tColInfo(c,"type") = ##class(Form.Util.Converter).sqlTypeToClass(tRS.GetColumnType(c))
			}
		}
		Else {
			Set tCols = tRS.%ResultColumnCount
			For c = 1:1:tCols {
				Set tColInfo(c,"name") = tRS.%Metadata.columns.GetAt(c).label
			}
		}
		Set ..sql = tOrigSQL

 		Set aet = {}.%FromJSON("{"""_..arrayName_""":[]}")
 		
 		// FORMS - debug
 		Set:$$$debug aet.sql = tOrigSQL
 		// END - FORMS - debug
 		
 		Set arrayNode = aet.%Get(..arrayName)
 	
 		// FORMS - pagination
		Set tStartRow = ..pageSize * (..currPage - 1)
		Set tEndRow = tStartRow + ..pageSize
		// END - FORMS - pagination

		// fetch and emit JSON
		// n.b. this should be pushed into the result set itself
		Set tRow = 0
		While (tRS.%Next(.tSC) && ((..maxRows = 0) || (tRow < ..maxRows)) && (tRow < tEndRow)) { // Последнее условие - FORMS - пагинация
			Quit:$$$ISERR(tSC)
			Set tRow = tRow + 1
			
			// FORMS - pagination
			CONTINUE:(tRow<=tStartRow)
			// END - FORMS - pagination
			
			Set node = {}
			For c = 1:1:tCols {
				Set tVal = tRS.%GetData(c)
				Set tOutVal = ##class(Form.Util.Converter).logicalToJSON($Get(tColInfo(c,"type")), tVal)
				Do node.%Set($Get(tColInfo(c,"name")), tOutVal)
				
				/*If ($IsValidNum(tVal)) {
					Do node.$set($Get(tColInfo(c,"name")),$Num(tVal),"number")
				}
				Else {
					Do node.$set($Get(tColInfo(c,"name")),tVal)
				}*/
			}
			Do arrayNode.%Push(node)
		}
		
		// FORMS - results count
		If nocount = $$$NO {
			While tRS.%Next() {}
			Set aet.total=tRS.%ROWCOUNT
		}
		// END - FORMS - results count
		
		// <MAXSTRING> fix
		// See https://community.intersystems.com/node/450911/
		Write ""
		Do aet.%ToJSON()
	}
	Catch(ex) {
		Set tSC = ex.AsStatus()
	}
	Quit tSC
}

Method %OnCreateResultSet(Output tSC As %Status, pInfo As %ZEN.Auxiliary.QueryInfo) As %ResultSet
{
	Set:$IsObject($Get(%request)) tMode = %request.Get("mode", 0)
	Set tRS = ##class(%ResultSet).%New()
	
	If $$$webContext {
		Set nocount = %request.Get("nocount", $$$NO)
	}
	
	If ((..currPage=1) && ($g(nocount, $$$NO)) && ($ZCVT($tr(..sql," "), "U") '[ "SELECTTOP")) {
		Set ..sql = $replace(..sql , "SELECT", "SELECT TOP " _ ..pageSize _ " ",,1,1)
	}
	
	Set tSC = tRS.Prepare(..sql)
	Set tRS.RuntimeMode = $Get(tMode, 0)
	Set pInfo.queryText = "sql: "_..sql
	Return tRS
}

}
